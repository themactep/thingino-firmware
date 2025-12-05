#ifndef WAKE_WORD_H
#define WAKE_WORD_H

#ifdef ENABLE_WAKE_WORD

#include <stdint.h>
#include <stdbool.h>
#include "esphome_plugin.h"

#ifdef __cplusplus
extern "C" {
#endif

// Wake word detection constants
#define WAKE_WORD_SAMPLE_RATE 16000
#define WAKE_WORD_WINDOW_DURATION_MS 30
#define WAKE_WORD_STRIDE_MS 10
#define WAKE_WORD_NUM_FEATURES 40

// Filterbank configuration
#define FILTERBANK_LOWER_BAND_LIMIT 125.0f
#define FILTERBANK_UPPER_BAND_LIMIT 7500.0f

// Ring buffer to hold ~120ms of audio (1920 samples at 16kHz)
#define WAKE_WORD_RING_BUFFER_MS 120
#define WAKE_WORD_RING_BUFFER_SAMPLES (WAKE_WORD_SAMPLE_RATE * WAKE_WORD_RING_BUFFER_MS / 1000)

// Detection thresholds
#define WAKE_WORD_DETECTION_THRESHOLD 0.65f  // Lowered from 0.85 for better detection
#define WAKE_WORD_SLIDING_WINDOW_AVERAGE_SIZE 5  // Reduced for faster response

// Model tensor arena size (needs to be large enough for stateful RNN models)
// Must be larger than the model size plus working memory
// Try 256KB to ensure we have enough space
#define WAKE_WORD_TENSOR_ARENA_SIZE (256 * 1024)  // 256KB

// Wake word model paths (can be configured at runtime)
#define WAKE_WORD_MODEL_DEFAULT_PATH "/etc/wake_word_model.tflite"

// Wake word state
typedef enum {
    WAKE_WORD_STATE_STOPPED = 0,
    WAKE_WORD_STATE_STARTING,
    WAKE_WORD_STATE_DETECTING,
    WAKE_WORD_STATE_STOPPING
} wake_word_state_t;

// Wake word detection callback
// Called when wake word is detected
// probability: confidence score (0.0 - 1.0)
typedef void (*wake_word_detected_callback_t)(float probability, void *userdata);

// Initialize wake word detection system
// ctx: ESPHome plugin context for logging
// model_path: path to TFLite model file (NULL for default)
// callback: function to call when wake word detected
// userdata: passed to callback
// Returns 0 on success, -1 on failure
int wake_word_init(esphome_plugin_context_t *ctx, const char *model_path,
                   wake_word_detected_callback_t callback, void *userdata);

// Start wake word detection
// Returns 0 on success, -1 on failure
int wake_word_start(void);

// Stop wake word detection
void wake_word_stop(void);

// Cleanup wake word detection system
void wake_word_cleanup(void);

// Get current detection state
wake_word_state_t wake_word_get_state(void);

// Check if wake word is enabled and model is loaded
bool wake_word_is_available(void);

#ifdef __cplusplus
}
#endif

#endif // ENABLE_WAKE_WORD

#endif // WAKE_WORD_H
