#ifdef ENABLE_WAKE_WORD

#include "wake_word.h"
#include "thingino_media_player.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <math.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/time.h>
#include <unistd.h>

// Audio output socket path (from thingino_media_player.h)
#define AUDIO_OUTPUT_SOCKET_PATH "ingenic_audio_output"

// Wake word chime sound file
#define WAKE_WORD_CHIME_PATH "/usr/share/sounds/th-chime_3.pcm"

// ESPMicroSpeechFeatures includes
#include "include/frontend.h"
#include "include/frontend_util.h"

// Cooldown period after detection to prevent double-triggering (in milliseconds)
#define WAKE_WORD_COOLDOWN_MS 2000

// Warmup period after starting detection - discard this many inferences
// This prevents false detections when resuming after playback due to stale model state
#define WAKE_WORD_WARMUP_INFERENCES 10

// TensorFlow Lite Micro includes
#include "tensorflow/lite/core/c/common.h"
#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/micro_resource_variable.h"
#include "tensorflow/lite/micro/micro_allocator.h"
#include "tensorflow/lite/schema/schema_generated.h"
#include "tensorflow/lite/kernels/internal/tensor_ctypes.h"

// Wake word context
typedef struct {
    esphome_plugin_context_t *plugin_ctx;
    wake_word_state_t state;
    pthread_mutex_t lock;

    // Audio ring buffer
    int16_t ring_buffer[WAKE_WORD_RING_BUFFER_SAMPLES];
    size_t ring_buffer_write_pos;
    size_t ring_buffer_read_pos;  // Position of next sample to read
    size_t ring_buffer_available;

    // Frontend for spectrogram generation
    struct FrontendConfig frontend_config;
    struct FrontendState frontend_state;
    bool frontend_initialized;

    // TFLite model
    uint8_t *model_data;
    size_t model_size;
    uint8_t *tensor_arena;  // Heap allocated for size
    uint8_t *var_arena;     // Heap allocated
    const tflite::Model *model;
    tflite::MicroAllocator *allocator;
    tflite::MicroResourceVariables *resource_variables;
    tflite::MicroInterpreter *interpreter;
    TfLiteTensor *input_tensor;
    TfLiteTensor *output_tensor;

    // Detection state
    float probability_history[WAKE_WORD_SLIDING_WINDOW_AVERAGE_SIZE];
    size_t probability_history_pos;
    float max_probability;

    // Stride handling for streaming models
    uint8_t model_stride;        // Number of feature frames per inference
    uint8_t current_stride_step; // Current position in stride

    // Cooldown to prevent double-triggering
    uint64_t last_detection_time_ms;  // Timestamp of last detection

    // Warmup counter - number of inferences to discard after starting
    int warmup_remaining;

    // Callbacks
    wake_word_detected_callback_t callback;
    void *userdata;

    // Detection thread
    pthread_t detection_thread;
    bool detection_active;
} wake_word_context_t;

static wake_word_context_t g_wake_word_ctx = {0};

// Forward declarations
static void audio_input_handler(const int16_t *buffer, size_t samples, void *userdata);
static void *detection_thread_func(void *arg);
static bool generate_features(int8_t *features_buffer);
static int run_inference(const int8_t *features, float *probability);
static bool load_model(const char *path);
static void unload_model(void);
static void play_wake_word_beep(void);

// Helper function to get current time in milliseconds
static uint64_t get_time_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + (uint64_t)tv.tv_usec / 1000;
}

// =============================================================================
// Wake Word Chime Playback
// =============================================================================

static void play_wake_word_beep(void) {
    // Open the chime PCM file
    FILE *f = fopen(WAKE_WORD_CHIME_PATH, "rb");
    if (!f) {
        fprintf(stderr, "[WakeWord] Failed to open chime file: %s\n", WAKE_WORD_CHIME_PATH);
        return;
    }

    // Get file size
    fseek(f, 0, SEEK_END);
    long file_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (file_size <= 0) {
        fprintf(stderr, "[WakeWord] Chime file is empty\n");
        fclose(f);
        return;
    }

    // Read the PCM data
    uint8_t *pcm_data = (uint8_t *)malloc(file_size);
    if (!pcm_data) {
        fprintf(stderr, "[WakeWord] Failed to allocate memory for chime\n");
        fclose(f);
        return;
    }

    size_t bytes_read = fread(pcm_data, 1, file_size, f);
    fclose(f);

    if (bytes_read != (size_t)file_size) {
        fprintf(stderr, "[WakeWord] Failed to read chime file\n");
        free(pcm_data);
        return;
    }

    // Connect to IAD audio output socket
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) {
        fprintf(stderr, "[WakeWord] Failed to create socket for chime\n");
        free(pcm_data);
        return;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    // Abstract socket (leading null byte)
    strncpy(&addr.sun_path[1], AUDIO_OUTPUT_SOCKET_PATH, sizeof(addr.sun_path) - 2);

    if (connect(sockfd, (struct sockaddr*)&addr,
                sizeof(sa_family_t) + strlen(&addr.sun_path[1]) + 1) == -1) {
        fprintf(stderr, "[WakeWord] Failed to connect to audio output for chime\n");
        close(sockfd);
        free(pcm_data);
        return;
    }

    // Write PCM data to audio output
    ssize_t written = write(sockfd, pcm_data, bytes_read);
    if (written < 0) {
        fprintf(stderr, "[WakeWord] Failed to write chime to audio output\n");
    } else {
        printf("[WakeWord] Played wake word chime (%zu bytes)\n", bytes_read);
    }

    close(sockfd);
    free(pcm_data);
}

// =============================================================================
// Audio Input Handler
// =============================================================================

static void audio_input_handler(const int16_t *buffer, size_t samples, void *userdata) {
    (void)userdata;
    static int callback_count = 0;
    static int16_t max_sample = 0;
    static int16_t min_sample = 0;

    callback_count++;

    pthread_mutex_lock(&g_wake_word_ctx.lock);

    // Copy samples to ring buffer and track audio levels
    for (size_t i = 0; i < samples; i++) {
        int16_t sample = buffer[i];
        g_wake_word_ctx.ring_buffer[g_wake_word_ctx.ring_buffer_write_pos] = sample;
        g_wake_word_ctx.ring_buffer_write_pos =
            (g_wake_word_ctx.ring_buffer_write_pos + 1) % WAKE_WORD_RING_BUFFER_SAMPLES;

        if (g_wake_word_ctx.ring_buffer_available < WAKE_WORD_RING_BUFFER_SAMPLES) {
            g_wake_word_ctx.ring_buffer_available++;
        }

        // Track min/max for level monitoring
        if (sample > max_sample) max_sample = sample;
        if (sample < min_sample) min_sample = sample;
    }

    pthread_mutex_unlock(&g_wake_word_ctx.lock);

    // Log audio input periodically
    if (callback_count == 1 || callback_count % 100 == 0) {
        fprintf(stderr, "[WakeWord] Audio input #%d: %zu samples, level range [%d, %d]\n",
                callback_count, samples, min_sample, max_sample);
        // Reset tracking
        max_sample = 0;
        min_sample = 0;
    }
}

// =============================================================================
// Feature Generation
// =============================================================================

static bool generate_features(int8_t *features_buffer) {
    static bool first_gen = true;
    static int gen_count = 0;

    pthread_mutex_lock(&g_wake_word_ctx.lock);

    // Calculate samples needed for one window and one stride
    size_t window_samples = (WAKE_WORD_SAMPLE_RATE * WAKE_WORD_WINDOW_DURATION_MS) / 1000;
    size_t stride_samples = (WAKE_WORD_SAMPLE_RATE * WAKE_WORD_STRIDE_MS) / 1000;

    // Always need at least window_samples available to generate features
    // We consume stride_samples each time (windows overlap)
    if (g_wake_word_ctx.ring_buffer_available < window_samples) {
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return false;
    }

    gen_count++;
    if (first_gen || gen_count % 100 == 0) {
        fprintf(stderr, "[WakeWord] generate_features #%d: window=%zu, stride=%zu, available=%zu, read_pos=%zu, write_pos=%zu\n",
                gen_count, window_samples, stride_samples, g_wake_word_ctx.ring_buffer_available,
                g_wake_word_ctx.ring_buffer_read_pos, g_wake_word_ctx.ring_buffer_write_pos);
    }

    // Get samples from ring buffer starting at read position
    // Max window at 16kHz = 30ms = 480 samples
    int16_t audio_samples[512];
    if (window_samples > 512) {
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return false;
    }

    // Read window_samples starting from read_pos and calculate energy
    int16_t sample_min = 32767, sample_max = -32768;
    int64_t energy = 0;  // Sum of squares for energy calculation
    for (size_t i = 0; i < window_samples; i++) {
        audio_samples[i] = g_wake_word_ctx.ring_buffer[
            (g_wake_word_ctx.ring_buffer_read_pos + i) % WAKE_WORD_RING_BUFFER_SAMPLES];
        if (audio_samples[i] < sample_min) sample_min = audio_samples[i];
        if (audio_samples[i] > sample_max) sample_max = audio_samples[i];
        energy += (int64_t)audio_samples[i] * (int64_t)audio_samples[i];
    }

    // Calculate RMS (Root Mean Square) energy
    float rms = sqrtf((float)energy / window_samples);

    // Skip processing if audio energy is too low (likely silence)
    // Threshold of ~100 RMS is reasonable for 16-bit audio
    const float MIN_AUDIO_ENERGY = 100.0f;
    if (rms < MIN_AUDIO_ENERGY) {
        if (first_gen || gen_count % 100 == 0) {
            fprintf(stderr, "[WakeWord] Skipping low energy audio: RMS=%.1f (min=%.1f)\n",
                    rms, MIN_AUDIO_ENERGY);
        }
        // Don't advance read position, just return
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return false;
    }

    // Log raw audio levels periodically
    if (first_gen || gen_count % 100 == 0) {
        fprintf(stderr, "[WakeWord] Raw audio samples: min=%d, max=%d, RMS=%.1f\n",
                sample_min, sample_max, rms);
    }

    // Advance read position by stride_samples (consuming that many samples)
    g_wake_word_ctx.ring_buffer_read_pos =
        (g_wake_word_ctx.ring_buffer_read_pos + stride_samples) % WAKE_WORD_RING_BUFFER_SAMPLES;
    g_wake_word_ctx.ring_buffer_available -= stride_samples;

    pthread_mutex_unlock(&g_wake_word_ctx.lock);

    // Generate spectrogram features
    size_t num_samples_read;
    struct FrontendOutput output = FrontendProcessSamples(
        &g_wake_word_ctx.frontend_state,
        audio_samples,
        window_samples,
        &num_samples_read
    );

    if (output.size != WAKE_WORD_NUM_FEATURES) {
        fprintf(stderr, "[WakeWord] generate_features: unexpected output size %zu (expected %d)\n",
                output.size, WAKE_WORD_NUM_FEATURES);
        return false;
    }

    // Quantize features to int8
    // Formula: input = (feature * 256) / (25.6 * 26.0) - 128
    // With rounding: value = ((feature * 256) + 333) / 666 - 128
    for (size_t i = 0; i < WAKE_WORD_NUM_FEATURES; i++) {
        int32_t value = ((output.values[i] * 256) + 333) / 666 - 128;
        if (value < -128) value = -128;
        if (value > 127) value = 127;
        features_buffer[i] = (int8_t)value;
    }

    // Log features periodically to debug
    if (first_gen || gen_count % 100 == 0) {
        fprintf(stderr, "[WakeWord] Features (first 10): ");
        for (int i = 0; i < 10 && i < WAKE_WORD_NUM_FEATURES; i++) {
            fprintf(stderr, "%d ", features_buffer[i]);
        }
        fprintf(stderr, "...\n");

        // Also log raw frontend output for first gen
        if (first_gen) {
            fprintf(stderr, "[WakeWord] Raw frontend values (first 10): ");
            for (int i = 0; i < 10 && i < (int)output.size; i++) {
                fprintf(stderr, "%u ", output.values[i]);
            }
            fprintf(stderr, "...\n");
        }
    }

    if (first_gen) {
        fprintf(stderr, "[WakeWord] Feature generation complete, num_samples_read=%zu\n", num_samples_read);
        first_gen = false;
    }

    return true;
}

// =============================================================================
// TFLite Inference
// =============================================================================

// Returns: 0 = error, 1 = accumulating features (no inference), 2 = inference complete
static int run_inference(const int8_t *features, float *probability) {
    static bool first_run = true;
    static int inference_count = 0;

    if (!g_wake_word_ctx.interpreter || !g_wake_word_ctx.input_tensor || !g_wake_word_ctx.output_tensor) {
        fprintf(stderr, "[WakeWord] run_inference: null pointers\n");
        return 0;
    }

    // Use tflite::GetTensorData for safe tensor data access
    int8_t *input_data = tflite::GetTensorData<int8_t>(g_wake_word_ctx.input_tensor);

    if (!input_data) {
        fprintf(stderr, "[WakeWord] Input data pointer is null\n");
        return 0;
    }

    // Copy features to the correct position in the input tensor based on stride
    // Input tensor shape is [1, stride, 40] - we fill one slice at a time
    size_t offset = g_wake_word_ctx.current_stride_step * WAKE_WORD_NUM_FEATURES;
    memcpy(input_data + offset, features, WAKE_WORD_NUM_FEATURES);

    g_wake_word_ctx.current_stride_step++;

    // Only run inference when we've accumulated enough feature frames
    if (g_wake_word_ctx.current_stride_step < g_wake_word_ctx.model_stride) {
        // Still accumulating features, no inference yet
        *probability = 0.0f;
        return 1;  // Accumulating
    }

    // Reset stride counter for next batch
    g_wake_word_ctx.current_stride_step = 0;

    if (first_run) {
        fprintf(stderr, "[WakeWord] Running first inference with stride=%d\n", g_wake_word_ctx.model_stride);
    }

    // Run inference
    TfLiteStatus status = g_wake_word_ctx.interpreter->Invoke();

    if (status != kTfLiteOk) {
        fprintf(stderr, "[WakeWord] Inference failed with status %d\n", status);
        return 0;
    }

    // Get output probability using safe accessor
    uint8_t *output_data = tflite::GetTensorData<uint8_t>(g_wake_word_ctx.output_tensor);

    if (!output_data) {
        fprintf(stderr, "[WakeWord] Output data pointer is null\n");
        return 0;
    }

    // The output is uint8, scale to 0-1 range
    *probability = output_data[0] / 255.0f;

    inference_count++;

    // Log inference results
    if (first_run || inference_count <= 10 || inference_count % 50 == 0) {
        fprintf(stderr, "[WakeWord] Inference #%d complete, probability: %.3f (raw=%u)\n",
                inference_count, *probability, output_data[0]);
    }

    if (first_run) {
        first_run = false;
    }

    return 2;  // Inference complete
}

// =============================================================================
// Model Loading
// =============================================================================

static bool load_model(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "[WakeWord] Failed to open model file: %s\n", path);
        return false;
    }

    // Get file size
    fseek(f, 0, SEEK_END);
    g_wake_word_ctx.model_size = ftell(f);
    fseek(f, 0, SEEK_SET);

    // Allocate and read model
    g_wake_word_ctx.model_data = (uint8_t *)malloc(g_wake_word_ctx.model_size);
    if (!g_wake_word_ctx.model_data) {
        fclose(f);
        return false;
    }

    if (fread(g_wake_word_ctx.model_data, 1, g_wake_word_ctx.model_size, f) != g_wake_word_ctx.model_size) {
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        fclose(f);
        return false;
    }

    fclose(f);

    fprintf(stderr, "[WakeWord] Model file read: %zu bytes\n", g_wake_word_ctx.model_size);

    // Get the model
    g_wake_word_ctx.model = tflite::GetModel(g_wake_word_ctx.model_data);
    if (!g_wake_word_ctx.model) {
        fprintf(stderr, "[WakeWord] Invalid TFLite model\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    fprintf(stderr, "[WakeWord] TFLite model parsed successfully\n");

    // Create op resolver with necessary ops for wake word models
    // Match the ops used by ESPHome's micro_wake_word component
    // Note: resolver must be static as it's referenced by the interpreter
    // Only populate once to avoid duplicate op registrations
    static tflite::MicroMutableOpResolver<20> resolver;
    static bool resolver_initialized = false;
    if (!resolver_initialized) {
        resolver.AddCallOnce();
        resolver.AddVarHandle();
        resolver.AddReshape();
        resolver.AddReadVariable();
        resolver.AddStridedSlice();
        resolver.AddConcatenation();
        resolver.AddAssignVariable();
        resolver.AddConv2D();
        resolver.AddMul();
        resolver.AddAdd();
        resolver.AddMean();
        resolver.AddFullyConnected();
        resolver.AddLogistic();
        resolver.AddQuantize();
        resolver.AddDepthwiseConv2D();
        resolver.AddAveragePool2D();
        resolver.AddMaxPool2D();
        resolver.AddPad();
        resolver.AddPack();
        resolver.AddSplitV();
        resolver_initialized = true;
    }

    fprintf(stderr, "[WakeWord] Op resolver configured with 20 operators\n");

    // Create allocator from separate variable arena for resource variables
    // Use 4096 directly since var_arena is now a heap-allocated pointer
    g_wake_word_ctx.allocator = tflite::MicroAllocator::Create(
        g_wake_word_ctx.var_arena, 4096);

    if (!g_wake_word_ctx.allocator) {
        fprintf(stderr, "[WakeWord] Failed to create allocator for resource variables\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    // Create resource variables for stateful models (RNN/LSTM)
    g_wake_word_ctx.resource_variables =
        tflite::MicroResourceVariables::Create(g_wake_word_ctx.allocator, 20);  // Allow up to 20 resource variables

    if (!g_wake_word_ctx.resource_variables) {
        fprintf(stderr, "[WakeWord] Failed to create resource variables\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    // Build interpreter with tensor arena and resource variables
    // (matching ESPHome's approach)
    fprintf(stderr, "[WakeWord] Creating interpreter with arena size %d\n", WAKE_WORD_TENSOR_ARENA_SIZE);
    g_wake_word_ctx.interpreter = new tflite::MicroInterpreter(
        g_wake_word_ctx.model, resolver, g_wake_word_ctx.tensor_arena, WAKE_WORD_TENSOR_ARENA_SIZE,
        g_wake_word_ctx.resource_variables
    );

    fprintf(stderr, "[WakeWord] Interpreter created, allocating tensors...\n");

    // Allocate tensors
    if (g_wake_word_ctx.interpreter->AllocateTensors() != kTfLiteOk) {
        fprintf(stderr, "[WakeWord] Failed to allocate tensors\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    fprintf(stderr, "[WakeWord] Tensors allocated successfully\n");

    // Verify interpreter is valid
    if (!g_wake_word_ctx.interpreter) {
        fprintf(stderr, "[WakeWord] Interpreter is null after creation!\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    // Check tensor counts
    size_t num_inputs = g_wake_word_ctx.interpreter->inputs_size();
    size_t num_outputs = g_wake_word_ctx.interpreter->outputs_size();
    fprintf(stderr, "[WakeWord] Model has %zu inputs and %zu outputs\n", num_inputs, num_outputs);

    if (num_inputs == 0) {
        fprintf(stderr, "[WakeWord] Model has no inputs\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    if (num_outputs == 0) {
        fprintf(stderr, "[WakeWord] Model has no outputs\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    // Get input and output tensors (same API as ESPHome uses)
    g_wake_word_ctx.input_tensor = g_wake_word_ctx.interpreter->input(0);
    if (!g_wake_word_ctx.input_tensor) {
        fprintf(stderr, "[WakeWord] Failed to get input tensor\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    g_wake_word_ctx.output_tensor = g_wake_word_ctx.interpreter->output(0);
    if (!g_wake_word_ctx.output_tensor) {
        fprintf(stderr, "[WakeWord] Failed to get output tensor\n");
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    // Log detailed tensor information
    int8_t *input_data_ptr = tflite::GetTensorData<int8_t>(g_wake_word_ctx.input_tensor);
    uint8_t *output_data_ptr = tflite::GetTensorData<uint8_t>(g_wake_word_ctx.output_tensor);
    fprintf(stderr, "[WakeWord] Input tensor: type=%d, bytes=%zu, data=%p\n",
            g_wake_word_ctx.input_tensor->type, g_wake_word_ctx.input_tensor->bytes,
            (void*)input_data_ptr);
    fprintf(stderr, "[WakeWord] Output tensor: type=%d, bytes=%zu, data=%p\n",
            g_wake_word_ctx.output_tensor->type, g_wake_word_ctx.output_tensor->bytes,
            (void*)output_data_ptr);

    // Check if input and output overlap
    if ((void*)output_data_ptr >= (void*)input_data_ptr &&
        (void*)output_data_ptr < (void*)(input_data_ptr + g_wake_word_ctx.input_tensor->bytes)) {
        fprintf(stderr, "[WakeWord] WARNING: Output tensor overlaps with input tensor!\n");
    }

    // Validate input tensor dimensions
    // Expected shape: [1, stride, 40] for streaming wake word models
    TfLiteIntArray* input_dims = g_wake_word_ctx.input_tensor->dims;
    if (!input_dims || input_dims->size != 3) {
        fprintf(stderr, "[WakeWord] Unexpected input tensor dimensions (size=%d, expected 3)\n",
                input_dims ? input_dims->size : 0);
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    // Log output tensor dimensions
    TfLiteIntArray* output_dims = g_wake_word_ctx.output_tensor->dims;
    if (output_dims) {
        fprintf(stderr, "[WakeWord] Output tensor dims: size=%d, shape=[", output_dims->size);
        for (int i = 0; i < output_dims->size; i++) {
            fprintf(stderr, "%d%s", output_dims->data[i], i < output_dims->size - 1 ? "," : "");
        }
        fprintf(stderr, "]\n");
    }

    // Calculate stride from tensor dimensions
    // dims[0] = batch (should be 1)
    // dims[1] = stride (number of feature frames per inference)
    // dims[2] = features (should be 40)
    g_wake_word_ctx.model_stride = input_dims->data[1];
    g_wake_word_ctx.current_stride_step = 0;

    if (input_dims->data[2] != WAKE_WORD_NUM_FEATURES) {
        fprintf(stderr, "[WakeWord] Unexpected feature size %d (expected %d)\n",
                input_dims->data[2], WAKE_WORD_NUM_FEATURES);
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
        return false;
    }

    if (g_wake_word_ctx.model_stride < 1) {
        g_wake_word_ctx.model_stride = 1;
    }

    // Verify input type is int8 (type 9 = kTfLiteInt8)
    if (g_wake_word_ctx.input_tensor->type != kTfLiteInt8) {
        fprintf(stderr, "[WakeWord] Warning: Input tensor type is %d, expected kTfLiteInt8 (9)\n",
                g_wake_word_ctx.input_tensor->type);
    }

    // Verify output type is uint8 (type 3 = kTfLiteUInt8)
    if (g_wake_word_ctx.output_tensor->type != kTfLiteUInt8) {
        fprintf(stderr, "[WakeWord] Warning: Output tensor type is %d, expected kTfLiteUInt8 (3)\n",
                g_wake_word_ctx.output_tensor->type);
    }

    fprintf(stderr, "[WakeWord] Model loaded: %zu bytes, input shape [%d,%d,%d], stride=%d\n",
            g_wake_word_ctx.model_size,
            input_dims->data[0], input_dims->data[1], input_dims->data[2],
            g_wake_word_ctx.model_stride);

    return true;
}

static void unload_model(void) {
    if (g_wake_word_ctx.interpreter) {
        delete g_wake_word_ctx.interpreter;
        g_wake_word_ctx.interpreter = NULL;
    }

    g_wake_word_ctx.input_tensor = NULL;
    g_wake_word_ctx.output_tensor = NULL;
    g_wake_word_ctx.model = NULL;
    g_wake_word_ctx.allocator = NULL;
    g_wake_word_ctx.resource_variables = NULL;

    if (g_wake_word_ctx.model_data) {
        free(g_wake_word_ctx.model_data);
        g_wake_word_ctx.model_data = NULL;
    }

    if (g_wake_word_ctx.tensor_arena) {
        free(g_wake_word_ctx.tensor_arena);
        g_wake_word_ctx.tensor_arena = NULL;
    }

    if (g_wake_word_ctx.var_arena) {
        free(g_wake_word_ctx.var_arena);
        g_wake_word_ctx.var_arena = NULL;
    }
}

// =============================================================================
// Detection Thread
// =============================================================================

static void *detection_thread_func(void *arg) {
    (void)arg;

    printf("[WakeWord] Detection thread started\n");

    int8_t features[WAKE_WORD_NUM_FEATURES];
    float probability;
    struct timespec sleep_time = {0, WAKE_WORD_STRIDE_MS * 1000000};
    int inference_count = 0;
    int loop_count = 0;

    while (1) {
        loop_count++;

        // Check for shutdown request
        if (media_player_is_shutdown_requested()) {
            fprintf(stderr, "[WakeWord] Detection thread: shutdown requested, exiting\n");
            break;
        }

        pthread_mutex_lock(&g_wake_word_ctx.lock);
        bool active = g_wake_word_ctx.detection_active;
        pthread_mutex_unlock(&g_wake_word_ctx.lock);

        if (!active) {
            fprintf(stderr, "[WakeWord] Detection thread: active=false, exiting\n");
            break;
        }

        // Generate features from audio
        if (generate_features(features)) {
            // Run inference (may just accumulate features if stride > 1)
            int result = run_inference(features, &probability);
            if (result == 0) {
                // Error - stop detection
                fprintf(stderr, "[WakeWord] Inference error, stopping detection\n");
                break;
            } else if (result == 2) {
                // Inference complete - process probability
                inference_count++;

                // Check if we're still in warmup period
                pthread_mutex_lock(&g_wake_word_ctx.lock);
                if (g_wake_word_ctx.warmup_remaining > 0) {
                    g_wake_word_ctx.warmup_remaining--;
                    if (g_wake_word_ctx.warmup_remaining == 0) {
                        fprintf(stderr, "[WakeWord] Warmup complete, detection active (discarded %d inferences)\n",
                                WAKE_WORD_WARMUP_INFERENCES);
                    } else if (inference_count <= 3 || g_wake_word_ctx.warmup_remaining % 3 == 0) {
                        fprintf(stderr, "[WakeWord] Warmup: discarding inference #%d (prob=%.3f), %d remaining\n",
                                inference_count, probability, g_wake_word_ctx.warmup_remaining);
                    }
                    pthread_mutex_unlock(&g_wake_word_ctx.lock);
                    continue;  // Skip detection during warmup
                }

                // Update probability history

                g_wake_word_ctx.probability_history[g_wake_word_ctx.probability_history_pos] = probability;
                g_wake_word_ctx.probability_history_pos =
                    (g_wake_word_ctx.probability_history_pos + 1) % WAKE_WORD_SLIDING_WINDOW_AVERAGE_SIZE;

                if (probability > g_wake_word_ctx.max_probability) {
                    g_wake_word_ctx.max_probability = probability;
                }

                // Calculate sliding average
                float avg = 0.0f;
                for (int i = 0; i < WAKE_WORD_SLIDING_WINDOW_AVERAGE_SIZE; i++) {
                    avg += g_wake_word_ctx.probability_history[i];
                }
                avg /= WAKE_WORD_SLIDING_WINDOW_AVERAGE_SIZE;

                wake_word_detected_callback_t callback = g_wake_word_ctx.callback;
                void *userdata = g_wake_word_ctx.userdata;
                pthread_mutex_unlock(&g_wake_word_ctx.lock);

                // Log more frequently when probability is elevated
                bool is_elevated = probability > 0.3f || avg > 0.3f;
                if (inference_count % 50 == 0 || is_elevated) {
                    fprintf(stderr, "[WakeWord] Detection loop #%d: prob=%.3f, avg=%.3f, max=%.3f, threshold=%.2f%s\n",
                            inference_count, probability, avg, g_wake_word_ctx.max_probability,
                            WAKE_WORD_DETECTION_THRESHOLD, is_elevated ? " [ELEVATED]" : "");
                }

                // Check if wake word detected - also check peak probability
                bool avg_detected = avg >= WAKE_WORD_DETECTION_THRESHOLD;
                bool peak_detected = probability >= (WAKE_WORD_DETECTION_THRESHOLD + 0.1f);  // Higher threshold for single sample

                if ((avg_detected || peak_detected) && callback) {
                    // Check cooldown to prevent double-triggering
                    uint64_t now = get_time_ms();
                    uint64_t elapsed = now - g_wake_word_ctx.last_detection_time_ms;

                    if (elapsed < WAKE_WORD_COOLDOWN_MS) {
                        // Still in cooldown period, ignore this detection
                        if (inference_count % 50 == 0) {
                            fprintf(stderr, "[WakeWord] Detection suppressed (cooldown: %llu ms remaining)\n",
                                    (unsigned long long)(WAKE_WORD_COOLDOWN_MS - elapsed));
                        }
                    } else {
                        const char *method = avg_detected ? "average" : "peak";
                        printf("[WakeWord] *** DETECTED via %s! *** prob=%.2f, avg=%.2f, max=%.2f\n",
                               method, probability, avg, g_wake_word_ctx.max_probability);

                        // Update last detection time
                        g_wake_word_ctx.last_detection_time_ms = now;

                        // Play confirmation chime
                        play_wake_word_beep();

                        // Reset detection state
                        pthread_mutex_lock(&g_wake_word_ctx.lock);
                        memset(g_wake_word_ctx.probability_history, 0, sizeof(g_wake_word_ctx.probability_history));
                        g_wake_word_ctx.max_probability = 0.0f;
                        g_wake_word_ctx.current_stride_step = 0;
                        pthread_mutex_unlock(&g_wake_word_ctx.lock);

                        // Call callback
                        callback(avg, userdata);
                    }
                }
            }
            // result == 1 means accumulating, just continue
        } else {
            // No features available yet, log occasionally
            if (loop_count % 1000 == 0) {
                pthread_mutex_lock(&g_wake_word_ctx.lock);
                fprintf(stderr, "[WakeWord] Waiting for audio: available=%zu samples\n",
                        g_wake_word_ctx.ring_buffer_available);
                pthread_mutex_unlock(&g_wake_word_ctx.lock);
            }
        }

        // Sleep for stride duration
        nanosleep(&sleep_time, NULL);
    }

    printf("[WakeWord] Detection thread exiting\n");
    return NULL;
}

// =============================================================================
// Public API
// =============================================================================

int wake_word_init(esphome_plugin_context_t *ctx, const char *model_path,
                   wake_word_detected_callback_t callback, void *userdata) {

    if (g_wake_word_ctx.state != WAKE_WORD_STATE_STOPPED) {
        fprintf(stderr, "[WakeWord] Already initialized\n");
        return -1;
    }

    memset(&g_wake_word_ctx, 0, sizeof(g_wake_word_ctx));
    g_wake_word_ctx.plugin_ctx = ctx;
    g_wake_word_ctx.callback = callback;
    g_wake_word_ctx.userdata = userdata;

    pthread_mutex_init(&g_wake_word_ctx.lock, NULL);

    // Allocate tensor arenas on heap
    // Use posix_memalign for 16-byte alignment required by TFLite
    if (posix_memalign((void**)&g_wake_word_ctx.tensor_arena, 16, WAKE_WORD_TENSOR_ARENA_SIZE) != 0) {
        fprintf(stderr, "[WakeWord] Failed to allocate tensor arena\n");
        return -1;
    }

    if (posix_memalign((void**)&g_wake_word_ctx.var_arena, 16, 4096) != 0) {
        fprintf(stderr, "[WakeWord] Failed to allocate var arena\n");
        free(g_wake_word_ctx.tensor_arena);
        return -1;
    }

    fprintf(stderr, "[WakeWord] Allocated tensor arena: %d bytes, var arena: %d bytes\n",
            WAKE_WORD_TENSOR_ARENA_SIZE, 4096);

    // Initialize frontend configuration - set everything explicitly to match ESPHome
    // Don't rely on FrontendFillConfigWithDefaults as it may set conflicting values
    memset(&g_wake_word_ctx.frontend_config, 0, sizeof(g_wake_word_ctx.frontend_config));

    // Window settings
    g_wake_word_ctx.frontend_config.window.size_ms = WAKE_WORD_WINDOW_DURATION_MS;
    g_wake_word_ctx.frontend_config.window.step_size_ms = WAKE_WORD_STRIDE_MS;

    // Filterbank settings
    g_wake_word_ctx.frontend_config.filterbank.num_channels = WAKE_WORD_NUM_FEATURES;
    g_wake_word_ctx.frontend_config.filterbank.lower_band_limit = FILTERBANK_LOWER_BAND_LIMIT;
    g_wake_word_ctx.frontend_config.filterbank.upper_band_limit = FILTERBANK_UPPER_BAND_LIMIT;

    // Noise reduction settings (from ESPHome preprocessor_settings.h)
    g_wake_word_ctx.frontend_config.noise_reduction.smoothing_bits = 10;
    g_wake_word_ctx.frontend_config.noise_reduction.even_smoothing = 0.025f;
    g_wake_word_ctx.frontend_config.noise_reduction.odd_smoothing = 0.06f;
    g_wake_word_ctx.frontend_config.noise_reduction.min_signal_remaining = 0.05f;

    // PCAN gain control settings
    g_wake_word_ctx.frontend_config.pcan_gain_control.enable_pcan = 1;
    g_wake_word_ctx.frontend_config.pcan_gain_control.strength = 0.95f;
    g_wake_word_ctx.frontend_config.pcan_gain_control.offset = 80.0f;
    g_wake_word_ctx.frontend_config.pcan_gain_control.gain_bits = 21;

    // Log scale settings
    g_wake_word_ctx.frontend_config.log_scale.enable_log = 1;
    g_wake_word_ctx.frontend_config.log_scale.scale_shift = 6;

    // Populate frontend state
    fprintf(stderr, "[WakeWord] Initializing frontend: window=%dms, stride=%dms, channels=%d, sample_rate=%d\n",
            g_wake_word_ctx.frontend_config.window.size_ms,
            g_wake_word_ctx.frontend_config.window.step_size_ms,
            g_wake_word_ctx.frontend_config.filterbank.num_channels,
            WAKE_WORD_SAMPLE_RATE);

    // FrontendPopulateState returns 1 on success, 0 on failure
    int frontend_result = FrontendPopulateState(&g_wake_word_ctx.frontend_config,
                                                 &g_wake_word_ctx.frontend_state,
                                                 WAKE_WORD_SAMPLE_RATE);
    if (frontend_result == 0) {
        fprintf(stderr, "[WakeWord] Failed to initialize frontend\n");
        return -1;
    }
    fprintf(stderr, "[WakeWord] Frontend initialized successfully\n");
    g_wake_word_ctx.frontend_initialized = true;

    // Load the model
    const char *path = model_path ? model_path : WAKE_WORD_MODEL_DEFAULT_PATH;
    if (!load_model(path)) {
        FrontendFreeStateContents(&g_wake_word_ctx.frontend_state);
        g_wake_word_ctx.frontend_initialized = false;
        return -1;
    }

    g_wake_word_ctx.state = WAKE_WORD_STATE_STOPPED;

    if (ctx) {
        esphome_plugin_log(ctx, 2, "[WakeWord] Initialized with model: %s", path);
    }

    return 0;
}

int wake_word_start(void) {
    pthread_mutex_lock(&g_wake_word_ctx.lock);

    if (g_wake_word_ctx.state != WAKE_WORD_STATE_STOPPED) {
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return -1;
    }

    g_wake_word_ctx.state = WAKE_WORD_STATE_STARTING;

    // Reset detection state
    g_wake_word_ctx.ring_buffer_write_pos = 0;
    g_wake_word_ctx.ring_buffer_read_pos = 0;  // Fix: Initialize read position
    g_wake_word_ctx.ring_buffer_available = 0;
    memset(g_wake_word_ctx.ring_buffer, 0, sizeof(g_wake_word_ctx.ring_buffer));  // Clear buffer
    memset(g_wake_word_ctx.probability_history, 0, sizeof(g_wake_word_ctx.probability_history));
    g_wake_word_ctx.probability_history_pos = 0;
    g_wake_word_ctx.max_probability = 0.0f;
    g_wake_word_ctx.current_stride_step = 0;
    g_wake_word_ctx.warmup_remaining = WAKE_WORD_WARMUP_INFERENCES;

    // Zero the input tensor to clear any stale data from previous session
    if (g_wake_word_ctx.input_tensor) {
        int8_t *input_data = tflite::GetTensorData<int8_t>(g_wake_word_ctx.input_tensor);
        if (input_data) {
            memset(input_data, 0, g_wake_word_ctx.input_tensor->bytes);
        }
    }

    // Reset resource variables (RNN/LSTM hidden state) to clear internal model state
    // This clears the internal model state that persists between inferences
    if (g_wake_word_ctx.resource_variables) {
        TfLiteStatus status = g_wake_word_ctx.resource_variables->ResetAll();
        if (status == kTfLiteOk) {
            fprintf(stderr, "[WakeWord] Reset model resource variables (RNN state)\n");
        } else {
            fprintf(stderr, "[WakeWord] Warning: Failed to reset resource variables\n");
        }
    }

    // Reset frontend
    FrontendReset(&g_wake_word_ctx.frontend_state);

    g_wake_word_ctx.detection_active = true;
    pthread_mutex_unlock(&g_wake_word_ctx.lock);

    // Start audio input
    if (media_player_start_audio_input(audio_input_handler, NULL) != 0) {
        pthread_mutex_lock(&g_wake_word_ctx.lock);
        g_wake_word_ctx.state = WAKE_WORD_STATE_STOPPED;
        g_wake_word_ctx.detection_active = false;
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return -1;
    }

    // Start detection thread with larger stack for TFLite
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setstacksize(&attr, 256 * 1024);  // 256KB stack for TFLite inference

    if (pthread_create(&g_wake_word_ctx.detection_thread, &attr, detection_thread_func, NULL) != 0) {
        pthread_attr_destroy(&attr);
        media_player_stop_audio_input();
        pthread_mutex_lock(&g_wake_word_ctx.lock);
        g_wake_word_ctx.state = WAKE_WORD_STATE_STOPPED;
        g_wake_word_ctx.detection_active = false;
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return -1;
    }
    pthread_attr_destroy(&attr);

    pthread_mutex_lock(&g_wake_word_ctx.lock);
    g_wake_word_ctx.state = WAKE_WORD_STATE_DETECTING;
    pthread_mutex_unlock(&g_wake_word_ctx.lock);

    printf("[WakeWord] Detection started\n");
    return 0;
}

void wake_word_stop(void) {
    pthread_mutex_lock(&g_wake_word_ctx.lock);

    if (g_wake_word_ctx.state != WAKE_WORD_STATE_DETECTING) {
        pthread_mutex_unlock(&g_wake_word_ctx.lock);
        return;
    }

    g_wake_word_ctx.state = WAKE_WORD_STATE_STOPPING;
    g_wake_word_ctx.detection_active = false;
    pthread_mutex_unlock(&g_wake_word_ctx.lock);

    // Stop audio input
    media_player_stop_audio_input();

    // Wait for detection thread
    pthread_join(g_wake_word_ctx.detection_thread, NULL);

    pthread_mutex_lock(&g_wake_word_ctx.lock);
    g_wake_word_ctx.state = WAKE_WORD_STATE_STOPPED;
    pthread_mutex_unlock(&g_wake_word_ctx.lock);

    printf("[WakeWord] Detection stopped\n");
}

void wake_word_cleanup(void) {
    wake_word_stop();

    unload_model();

    if (g_wake_word_ctx.frontend_initialized) {
        FrontendFreeStateContents(&g_wake_word_ctx.frontend_state);
        g_wake_word_ctx.frontend_initialized = false;
    }

    pthread_mutex_destroy(&g_wake_word_ctx.lock);

    printf("[WakeWord] Cleanup complete\n");
}

wake_word_state_t wake_word_get_state(void) {
    pthread_mutex_lock(&g_wake_word_ctx.lock);
    wake_word_state_t state = g_wake_word_ctx.state;
    pthread_mutex_unlock(&g_wake_word_ctx.lock);
    return state;
}

bool wake_word_is_available(void) {
    return g_wake_word_ctx.model_data != NULL && g_wake_word_ctx.frontend_initialized;
}

#endif // ENABLE_WAKE_WORD
