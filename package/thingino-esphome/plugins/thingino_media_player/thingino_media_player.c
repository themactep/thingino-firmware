#include "thingino_media_player.h"
#include "media_player_proto.h"
#include "switch_proto.h"
#include "esphome_proto.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <curl/curl.h>
#include <errno.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <poll.h>

#ifdef ENABLE_WAKE_WORD
#include "wake_word.h"
#endif

// Plugin metadata
static const char *plugin_name = "thingino_media_player";
static const char *plugin_version = "1.0.0";
static const uint32_t media_player_key = 1; // Entity key for this media player
static const uint32_t wake_word_switch_key = 2;

// Media player format purpose constants (if not defined in esphome_proto.h)
#ifndef MEDIA_PLAYER_FORMAT_PURPOSE_DEFAULT
#define MEDIA_PLAYER_FORMAT_PURPOSE_DEFAULT 0
#endif
#ifndef MEDIA_PLAYER_FORMAT_PURPOSE_ANNOUNCEMENT
#define MEDIA_PLAYER_FORMAT_PURPOSE_ANNOUNCEMENT 1
#endif

// Additional voice assistant feature flags (if not defined in esphome_proto.h)
#ifndef VOICE_ASSISTANT_FEATURE_ANNOUNCE
#define VOICE_ASSISTANT_FEATURE_ANNOUNCE (1 << 4)
#endif
#ifndef VOICE_ASSISTANT_FEATURE_START_CONVERSATION
#define VOICE_ASSISTANT_FEATURE_START_CONVERSATION (1 << 5)
#endif

// Global media player context
static MediaPlayerContext g_player_ctx = {
    .plugin_ctx = NULL,
    .state = MEDIA_PLAYER_STATE_IDLE,
    .volume = 0.7f,
    .muted = false,
    .audio_sock = -1,
    .playback_active = false,
    .current_url = NULL,
    .is_announcement = false,
#ifdef ENABLE_WAKE_WORD
    .audio_input_sock = -1,
    .audio_input_active = false,
    .audio_input_callback = NULL,
    .audio_input_userdata = NULL,
    .ha_stream_sock = -1,
    .ha_stream_port = 0,
    .ha_stream_host = {0},
    .ha_streaming_active = false
#endif
};

// Shutdown flag to allow graceful exit from blocking operations
static volatile bool g_shutdown_requested = false;

// Check if shutdown has been requested
bool media_player_is_shutdown_requested(void) {
    return g_shutdown_requested;
}

// Request shutdown - can be called from signal handlers
void media_player_request_shutdown(void) {
    g_shutdown_requested = true;
}

// Atexit handler for graceful shutdown
static void atexit_shutdown_handler(void) {
    fprintf(stderr, "[MediaPlayer] atexit handler called, requesting shutdown\n");
    g_shutdown_requested = true;

    // Give threads a moment to notice the shutdown flag
    usleep(200000);  // 200ms
}

// Register atexit handler for graceful shutdown
// NOTE: We don't install signal handlers because the main esphome-linux program
// needs to handle SIGINT/SIGTERM to exit its main loop. Installing our handler
// would prevent the main program from receiving the signal.
// Instead, we rely on:
// 1. atexit() - called when the program exits normally
// 2. media_player_cleanup() - called by esphome_plugin_cleanup_all() during shutdown
static void register_shutdown_handlers(void) {
    atexit(atexit_shutdown_handler);
}

#ifdef ENABLE_WAKE_WORD
// Track whether wake word was suspended by us (so we know to restart it)
static bool g_wake_word_suspended = false;

// Suspend wake word detection if it's currently active
// Returns true if wake word was suspended, false if it wasn't running
static bool suspend_wake_word(void) {
    if (wake_word_get_state() == WAKE_WORD_STATE_DETECTING) {
        wake_word_stop();
        g_wake_word_suspended = true;
        printf("[MediaPlayer] Wake word detection suspended\n");
        return true;
    }
    return false;
}

// Resume wake word detection if we previously suspended it
static void resume_wake_word(void) {
    if (g_wake_word_suspended) {
        g_wake_word_suspended = false;
        // Don't restart wake word during shutdown
        if (g_shutdown_requested) {
            printf("[MediaPlayer] Shutdown requested, not resuming wake word\n");
            return;
        }
        if (wake_word_start() == 0) {
            printf("[MediaPlayer] Wake word detection resumed\n");
        } else {
            fprintf(stderr, "[MediaPlayer] Failed to resume wake word detection\n");
        }
    }
}
#endif

// Supported audio formats for this device
// Must use media_player_supported_format_t which has: format, sample_rate, num_channels, purpose, sample_bytes
// Purpose: 0 = DEFAULT, 1 = ANNOUNCEMENT (for voice assistant TTS)
static const media_player_supported_format_t supported_formats[] = {
    {"wav", 16000, 1, MEDIA_PLAYER_FORMAT_PURPOSE_DEFAULT, 2},      // 16kHz mono 16-bit WAV (default playback)
    {"wav", 48000, 1, MEDIA_PLAYER_FORMAT_PURPOSE_DEFAULT, 2},      // 48kHz mono 16-bit WAV (default playback)
    {"wav", 16000, 1, MEDIA_PLAYER_FORMAT_PURPOSE_ANNOUNCEMENT, 2}, // 16kHz mono 16-bit WAV (for announcements/TTS)
};

// Forward declarations of static helper functions
static void report_media_player_state(MediaPlayerState state, float volume, bool muted);
static int iac_connect_audio_output(void);
static int iac_connect_control(void);
static int iac_send_control_command(const char *command, char *response, size_t response_size);
static bool iac_check_output_available(void);
static bool set_system_volume(float volume);
static float get_system_volume(void);
static size_t curl_write_to_iad(void *buffer, size_t size, size_t nmemb, void *userp);
static void *audio_streaming_thread(void *arg);
static bool download_and_stream_audio(const char *url, bool is_announcement);
static void stop_current_playback(void);
#ifdef ENABLE_WAKE_WORD
static int start_ha_audio_stream(const char *host, uint32_t port);
static int start_ha_api_audio_stream(int client_id);
static void stop_ha_audio_stream(void);

// LED control for voice assistant visual feedback
static void va_led_listening(void);    // Solid blue - microphone active
static void va_led_processing(void);   // Blinking blue - processing command
static void va_led_off(void);          // Turn off LED
#endif

// =============================================================================
// State Reporting to Home Assistant
// =============================================================================

static void report_media_player_state(MediaPlayerState state, float volume, bool muted) {
    if (!g_player_ctx.plugin_ctx) {
        fprintf(stderr, "[MediaPlayer] ERROR: plugin_ctx is NULL, cannot send state\n");
        return;
    }

    media_player_state_response_t state_msg = {
        .key = media_player_key,
        .state = state,
        .volume = volume,
        .muted = muted
    };

    uint8_t encode_buf[256];
    size_t len = media_player_encode_state_response(encode_buf, sizeof(encode_buf), &state_msg);

    if (len > 0) {
        esphome_plugin_send_message(g_player_ctx.plugin_ctx,
                                      ESPHOME_MSG_MEDIA_PLAYER_STATE_RESPONSE,
                                      encode_buf, len);
        esphome_plugin_log(g_player_ctx.plugin_ctx, 2,
                           "[MediaPlayer] State: %d, Volume: %.2f, Muted: %d", state, volume, muted);
    } else {
        esphome_plugin_log(g_player_ctx.plugin_ctx, 0,
                           "[MediaPlayer] Failed to encode state response");
    }
}

static void report_switch_state(uint32_t key, bool state) {

    uint8_t encode_buf[128];
    switch_state_response_t state_msg = {
        .key = key,
        .state = state
    };
    size_t len = switch_encode_state_response(encode_buf, sizeof(encode_buf), &state_msg);

    if (len > 0) {
        esphome_plugin_send_message(g_player_ctx.plugin_ctx,
                                        ESPHOME_MSG_SWITCH_STATE_RESPONSE,
                                        encode_buf, len);
        esphome_plugin_log(g_player_ctx.plugin_ctx, 2,
                            "[MediaPlayer] Switch state: %d", state_msg.state);
    } else {
        esphome_plugin_log(g_player_ctx.plugin_ctx, 0,
                            "[MediaPlayer] Failed to encode state response");
    }
}

// =============================================================================
// IAC (Ingenic Audio Client) Interface Functions
// =============================================================================

static int iac_connect_audio_output(void) {
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("[MediaPlayer] socket");
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    // Abstract socket (leading null byte)
    strncpy(&addr.sun_path[1], AUDIO_OUTPUT_SOCKET_PATH, sizeof(addr.sun_path) - 2);

    if (connect(sockfd, (struct sockaddr*)&addr,
                sizeof(sa_family_t) + strlen(&addr.sun_path[1]) + 1) == -1) {
        perror("[MediaPlayer] connect to audio output socket");
        close(sockfd);
        return -1;
    }

    printf("[MediaPlayer] Connected to IAD audio output socket\n");
    return sockfd;
}

static int iac_connect_control(void) {
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("[MediaPlayer] socket");
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(&addr.sun_path[1], AUDIO_CONTROL_SOCKET_PATH, sizeof(addr.sun_path) - 2);

    if (connect(sockfd, (struct sockaddr*)&addr,
                sizeof(sa_family_t) + strlen(&addr.sun_path[1]) + 1) == -1) {
        perror("[MediaPlayer] connect to control socket");
        close(sockfd);
        return -1;
    }

    return sockfd;
}

static int iac_send_control_command(const char *command, char *response, size_t response_size) {
    int ctrl_sock = iac_connect_control();
    if (ctrl_sock < 0) {
        return -1;
    }

    ssize_t sent = write(ctrl_sock, command, strlen(command));
    if (sent < 0) {
        perror("[MediaPlayer] write to control socket");
        close(ctrl_sock);
        return -1;
    }

    ssize_t received = recv(ctrl_sock, response, response_size - 1, 0);
    if (received < 0) {
        perror("[MediaPlayer] recv from control socket");
        close(ctrl_sock);
        return -1;
    }

    response[received] = '\0';
    close(ctrl_sock);
    return 0;
}

static bool iac_check_output_available(void) {
    char response[256];
    int result = iac_send_control_command("GET sampleVariableA", response, sizeof(response));
    return (result == 0);
}

#ifdef ENABLE_WAKE_WORD
// =============================================================================
// Audio Input Functions
// =============================================================================

static int iac_connect_audio_input(void) {
    int sockfd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (sockfd < 0) {
        perror("[MediaPlayer] socket");
        return -1;
    }

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    // Abstract socket (leading null byte)
    strncpy(&addr.sun_path[1], AUDIO_INPUT_SOCKET_PATH, sizeof(addr.sun_path) - 2);

    if (connect(sockfd, (struct sockaddr*)&addr,
                sizeof(sa_family_t) + strlen(&addr.sun_path[1]) + 1) == -1) {
        perror("[MediaPlayer] connect to audio input socket");
        close(sockfd);
        return -1;
    }

    printf("[MediaPlayer] Connected to IAD audio input socket\n");
    return sockfd;
}

static void *audio_input_thread(void *arg) {
    (void)arg;

    printf("[MediaPlayer] Audio input thread started\n");

    uint8_t buffer[AUDIO_INPUT_BUFFER_SIZE];
    ssize_t bytes_received;
    struct pollfd pfd;

    while (1) {
        // Check for shutdown
        if (g_shutdown_requested) {
            printf("[MediaPlayer] Audio input thread: shutdown requested\n");
            break;
        }

        pthread_mutex_lock(&g_player_ctx.lock);
        bool active = g_player_ctx.audio_input_active;
        int sockfd = g_player_ctx.audio_input_sock;
        audio_input_callback_t callback = g_player_ctx.audio_input_callback;
        void *userdata = g_player_ctx.audio_input_userdata;
        pthread_mutex_unlock(&g_player_ctx.lock);

        if (!active || sockfd < 0) {
            break;
        }

        // Use poll() with timeout so we can check shutdown flag periodically
        pfd.fd = sockfd;
        pfd.events = POLLIN;
        pfd.revents = 0;

        int poll_result = poll(&pfd, 1, 100);  // 100ms timeout
        if (poll_result < 0) {
            if (errno == EINTR) {
                continue;  // Interrupted by signal, check shutdown and retry
            }
            perror("[MediaPlayer] poll on audio input socket");
            break;
        } else if (poll_result == 0) {
            // Timeout - loop back to check shutdown flag
            continue;
        }

        // Check for errors or hangup
        if (pfd.revents & (POLLERR | POLLHUP | POLLNVAL)) {
            printf("[MediaPlayer] Audio input socket error or hangup\n");
            break;
        }

        // Data available, read it
        bytes_received = read(sockfd, buffer, AUDIO_INPUT_BUFFER_SIZE);
        if (bytes_received <= 0) {
            if (bytes_received < 0 && errno != EINTR) {
                perror("[MediaPlayer] read from audio input socket");
            }
            break;
        }

        // Call the callback with the audio data
        if (callback) {
            // Convert bytes to samples (16-bit = 2 bytes per sample)
            size_t samples = bytes_received / 2;
            callback((const int16_t *)buffer, samples, userdata);
        }
    }

    printf("[MediaPlayer] Audio input thread exiting\n");

    pthread_mutex_lock(&g_player_ctx.lock);
    if (g_player_ctx.audio_input_sock >= 0) {
        close(g_player_ctx.audio_input_sock);
        g_player_ctx.audio_input_sock = -1;
    }
    g_player_ctx.audio_input_active = false;
    pthread_mutex_unlock(&g_player_ctx.lock);

    return NULL;
}

int media_player_start_audio_input(audio_input_callback_t callback, void *userdata) {
    if (!callback) {
        fprintf(stderr, "[MediaPlayer] Audio input callback is NULL\n");
        return -1;
    }

    pthread_mutex_lock(&g_player_ctx.lock);

    // Stop any existing audio input
    if (g_player_ctx.audio_input_active && g_player_ctx.audio_input_sock >= 0) {
        close(g_player_ctx.audio_input_sock);
        g_player_ctx.audio_input_sock = -1;
        g_player_ctx.audio_input_active = false;
    }

    // Connect to audio input socket
    int sockfd = iac_connect_audio_input();
    if (sockfd < 0) {
        pthread_mutex_unlock(&g_player_ctx.lock);
        return -1;
    }

    // Send audio input request
    int request_type = AUDIO_INPUT_REQUEST;
    if (write(sockfd, &request_type, sizeof(int)) != sizeof(int)) {
        perror("[MediaPlayer] write audio input request");
        close(sockfd);
        pthread_mutex_unlock(&g_player_ctx.lock);
        return -1;
    }

    g_player_ctx.audio_input_sock = sockfd;
    g_player_ctx.audio_input_callback = callback;
    g_player_ctx.audio_input_userdata = userdata;
    g_player_ctx.audio_input_active = true;

    pthread_mutex_unlock(&g_player_ctx.lock);

    // Start the audio input thread
    if (pthread_create(&g_player_ctx.audio_input_thread, NULL, audio_input_thread, NULL) != 0) {
        perror("[MediaPlayer] pthread_create for audio input");
        pthread_mutex_lock(&g_player_ctx.lock);
        close(g_player_ctx.audio_input_sock);
        g_player_ctx.audio_input_sock = -1;
        g_player_ctx.audio_input_active = false;
        pthread_mutex_unlock(&g_player_ctx.lock);
        return -1;
    }

    printf("[MediaPlayer] Audio input started (16kHz 16-bit mono)\n");
    return 0;
}

void media_player_stop_audio_input(void) {
    pthread_mutex_lock(&g_player_ctx.lock);

    bool was_active = g_player_ctx.audio_input_active;
    pthread_t thread = g_player_ctx.audio_input_thread;

    if (was_active && g_player_ctx.audio_input_sock >= 0) {
        printf("[MediaPlayer] Stopping audio input\n");
        // Shutdown the socket first to unblock any pending read()
        shutdown(g_player_ctx.audio_input_sock, SHUT_RDWR);
        close(g_player_ctx.audio_input_sock);
        g_player_ctx.audio_input_sock = -1;
        g_player_ctx.audio_input_active = false;
    }

    pthread_mutex_unlock(&g_player_ctx.lock);

    // Wait for thread to finish only if it was active
    if (was_active && thread) {
        pthread_join(thread, NULL);
    }
}

// =============================================================================
// Audio Streaming to Home Assistant
// =============================================================================

static void ha_stream_audio_callback(const int16_t *buffer, size_t samples, void *userdata) {
    (void)userdata;

    pthread_mutex_lock(&g_player_ctx.lock);
    int sockfd = g_player_ctx.ha_stream_sock;
    bool active = g_player_ctx.ha_streaming_active;
    bool api_mode = g_player_ctx.ha_api_streaming;
    pthread_mutex_unlock(&g_player_ctx.lock);

    if (!active) {
        return;
    }

    if (api_mode) {
        // Send audio via ESPHome API message (VOICE_ASSISTANT_AUDIO type 106)
        // Format: raw 16-bit PCM, 16kHz, mono
        // Fields:
        //   1: bytes data (raw audio)
        //   2: bool end (if true, this is the last chunk)
        uint8_t msg_buf[2048];
        pb_buffer_t pb;
        pb_buffer_init_write(&pb, msg_buf, sizeof(msg_buf));

        // Field 1: audio data
        size_t audio_bytes = samples * sizeof(int16_t);
        pb_encode_bytes(&pb, 1, (const uint8_t *)buffer, audio_bytes);

        // Field 2: end = false (not the last chunk)
        pb_encode_bool(&pb, 2, false);

        if (!pb.error && pb.pos > 0 && g_player_ctx.plugin_ctx) {
            static int api_audio_count = 0;
            api_audio_count++;
            if (api_audio_count == 1 || api_audio_count % 100 == 0) {
                fprintf(stderr, "[MediaPlayer] Sending API audio chunk #%d: %zu samples (%zu bytes)\n",
                        api_audio_count, samples, audio_bytes);
            }
            esphome_plugin_send_message(g_player_ctx.plugin_ctx,
                                         ESPHOME_MSG_VOICE_ASSISTANT_AUDIO,
                                         msg_buf, pb.pos);
        }
    } else {
        // Send audio data over UDP to Home Assistant
        if (sockfd < 0) {
            return;
        }
        ssize_t sent = send(sockfd, buffer, samples * sizeof(int16_t), 0);
        if (sent < 0) {
            perror("[MediaPlayer] send to HA");
        }
    }
}

// Wait for any active audio playback to complete
// timeout_ms: maximum time to wait in milliseconds (0 = wait indefinitely)
// Returns true if playback completed, false if timed out or shutdown requested
static bool wait_for_playback_complete(uint32_t timeout_ms) {
    uint32_t elapsed = 0;
    const uint32_t poll_interval_ms = 50;

    while (1) {
        // Check for shutdown request
        if (g_shutdown_requested) {
            fprintf(stderr, "[MediaPlayer] Shutdown requested, aborting wait\n");
            return false;
        }

        pthread_mutex_lock(&g_player_ctx.lock);
        bool playing = g_player_ctx.playback_active;
        pthread_mutex_unlock(&g_player_ctx.lock);

        if (!playing) {
            return true;
        }

        if (timeout_ms > 0 && elapsed >= timeout_ms) {
            fprintf(stderr, "[MediaPlayer] Timeout waiting for playback to complete\n");
            return false;
        }

        usleep(poll_interval_ms * 1000);
        elapsed += poll_interval_ms;

        // Log progress every second
        if (elapsed % 1000 == 0) {
            fprintf(stderr, "[MediaPlayer] Waiting for playback to complete... (%u ms)\n", elapsed);
        }
    }
}

// Start API-based audio streaming (port=0 means stream via API)
static int start_ha_api_audio_stream(int client_id) {
    // Wait for any current playback to finish before starting to record
    // Use a 30 second timeout to avoid waiting forever
    if (!wait_for_playback_complete(30000)) {
        fprintf(stderr, "[MediaPlayer] Cannot start API audio stream - playback still active\n");
        return -1;
    }

    pthread_mutex_lock(&g_player_ctx.lock);

    // Stop any existing stream
    if (g_player_ctx.ha_streaming_active) {
        pthread_mutex_unlock(&g_player_ctx.lock);
        stop_ha_audio_stream();
        pthread_mutex_lock(&g_player_ctx.lock);
    }

    g_player_ctx.ha_stream_sock = -1;  // No UDP socket needed
    g_player_ctx.ha_stream_port = 0;
    g_player_ctx.ha_api_streaming = true;
    g_player_ctx.ha_stream_client_id = client_id;
    g_player_ctx.ha_streaming_active = true;

    pthread_mutex_unlock(&g_player_ctx.lock);

    // Suspend wake word detection while streaming
    suspend_wake_word();

    // Start audio input with our streaming callback
    if (media_player_start_audio_input(ha_stream_audio_callback, NULL) != 0) {
        pthread_mutex_lock(&g_player_ctx.lock);
        g_player_ctx.ha_streaming_active = false;
        g_player_ctx.ha_api_streaming = false;
        pthread_mutex_unlock(&g_player_ctx.lock);
        // Resume wake word detection
        resume_wake_word();
        return -1;
    }

    fprintf(stderr, "[MediaPlayer] Started streaming audio via API (client_id=%d)\n", client_id);
    return 0;
}

static int start_ha_audio_stream(const char *host, uint32_t port) {
    // Wait for any current playback to finish before starting to record
    // Use a 30 second timeout to avoid waiting forever
    if (!wait_for_playback_complete(30000)) {
        fprintf(stderr, "[MediaPlayer] Cannot start UDP audio stream - playback still active\n");
        return -1;
    }

    pthread_mutex_lock(&g_player_ctx.lock);

    // Stop any existing stream
    if (g_player_ctx.ha_streaming_active) {
        pthread_mutex_unlock(&g_player_ctx.lock);
        stop_ha_audio_stream();
        pthread_mutex_lock(&g_player_ctx.lock);
    }

    // Create UDP socket
    int sockfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (sockfd < 0) {
        perror("[MediaPlayer] socket for HA stream");
        pthread_mutex_unlock(&g_player_ctx.lock);
        return -1;
    }

    // Resolve hostname
    struct hostent *he = gethostbyname(host);
    if (!he) {
        fprintf(stderr, "[MediaPlayer] Failed to resolve host: %s\n", host);
        close(sockfd);
        pthread_mutex_unlock(&g_player_ctx.lock);
        return -1;
    }

    // Setup destination address
    struct sockaddr_in dest_addr;
    memset(&dest_addr, 0, sizeof(dest_addr));
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons(port);
    memcpy(&dest_addr.sin_addr, he->h_addr_list[0], he->h_length);

    // Connect UDP socket (so we can use send() instead of sendto())
    if (connect(sockfd, (struct sockaddr *)&dest_addr, sizeof(dest_addr)) < 0) {
        perror("[MediaPlayer] connect UDP socket");
        close(sockfd);
        pthread_mutex_unlock(&g_player_ctx.lock);
        return -1;
    }

    g_player_ctx.ha_stream_sock = sockfd;
    g_player_ctx.ha_stream_port = port;
    strncpy(g_player_ctx.ha_stream_host, host, sizeof(g_player_ctx.ha_stream_host) - 1);
    g_player_ctx.ha_streaming_active = true;
    g_player_ctx.ha_api_streaming = false;  // UDP mode, not API mode

    pthread_mutex_unlock(&g_player_ctx.lock);

    // Suspend wake word detection while streaming
    suspend_wake_word();

    // Start audio input with our streaming callback
    if (media_player_start_audio_input(ha_stream_audio_callback, NULL) != 0) {
        pthread_mutex_lock(&g_player_ctx.lock);
        close(g_player_ctx.ha_stream_sock);
        g_player_ctx.ha_stream_sock = -1;
        g_player_ctx.ha_streaming_active = false;
        pthread_mutex_unlock(&g_player_ctx.lock);
        // Resume wake word detection
        resume_wake_word();
        return -1;
    }

    printf("[MediaPlayer] Started streaming audio to %s:%u\n", host, port);
    return 0;
}

// Stop HA audio streaming
// resume_wake_word_after: if true, resume wake word detection after stopping
//                         set to false if TTS playback will follow (playback will resume it)
static void stop_ha_audio_stream_internal(bool resume_wake_word_after) {
    pthread_mutex_lock(&g_player_ctx.lock);

    if (!g_player_ctx.ha_streaming_active) {
        pthread_mutex_unlock(&g_player_ctx.lock);
        return;
    }

    bool was_api_mode = g_player_ctx.ha_api_streaming;
    g_player_ctx.ha_streaming_active = false;
    g_player_ctx.ha_api_streaming = false;
    pthread_mutex_unlock(&g_player_ctx.lock);

    // Stop audio input
    media_player_stop_audio_input();

    // If we were streaming via API, send an end message
    if (was_api_mode && g_player_ctx.plugin_ctx) {
        uint8_t msg_buf[16];
        pb_buffer_t pb;
        pb_buffer_init_write(&pb, msg_buf, sizeof(msg_buf));

        // Field 1: empty data
        pb_encode_bytes(&pb, 1, NULL, 0);

        // Field 2: end = true (signal end of audio stream)
        pb_encode_bool(&pb, 2, true);

        if (!pb.error && pb.pos > 0) {
            esphome_plugin_send_message(g_player_ctx.plugin_ctx,
                                         ESPHOME_MSG_VOICE_ASSISTANT_AUDIO,
                                         msg_buf, pb.pos);
            printf("[MediaPlayer] Sent end-of-audio marker to HA\n");
        }
    }

    pthread_mutex_lock(&g_player_ctx.lock);
    if (g_player_ctx.ha_stream_sock >= 0) {
        close(g_player_ctx.ha_stream_sock);
        g_player_ctx.ha_stream_sock = -1;
    }
    g_player_ctx.ha_stream_port = 0;
    pthread_mutex_unlock(&g_player_ctx.lock);

    if (was_api_mode) {
        printf("[MediaPlayer] Stopped streaming audio via API\n");
    } else {
        printf("[MediaPlayer] Stopped streaming audio to HA (UDP)\n");
    }

    // Resume wake word detection if requested
    if (resume_wake_word_after) {
        resume_wake_word();
    }
}

// Stop HA audio streaming and resume wake word detection
static void stop_ha_audio_stream(void) {
    stop_ha_audio_stream_internal(true);
}

// =============================================================================
// LED Control for Voice Assistant Feedback
// =============================================================================

static pid_t va_led_blink_pid = 0;

// Stop any running blink process
static void va_led_stop_blink(void) {
    if (va_led_blink_pid > 0) {
        // Send SIGKILL to ensure it dies
        kill(va_led_blink_pid, SIGKILL);
        waitpid(va_led_blink_pid, NULL, 0);
        va_led_blink_pid = 0;
    }
}

// Solid blue LED - microphone is active/listening
static void va_led_listening(void) {
    va_led_stop_blink();
    system("led blue");
    fprintf(stderr, "[MediaPlayer] LED: listening (solid blue)\n");
}

// Blinking blue LED - processing command over network
// Quick random pulses: 2-5 blinks, then random pause (100-500ms), repeat
static void va_led_processing(void) {
    va_led_stop_blink();

    // Fork a process to blink the LED
    pid_t pid = fork();
    if (pid == 0) {
        // Child process - rapid random pulse pattern
        // Seed random with time and pid for variety
        srand(time(NULL) ^ getpid());

        while (1) {
            // Random number of quick pulses (2-5)
            int num_pulses = 2 + (rand() % 4);

            for (int i = 0; i < num_pulses; i++) {
                system("led blue");
                usleep(50000);   // 50ms on (very quick)
                system("led off");
                usleep(50000);   // 50ms off
            }

            // Random pause between pulse groups (100-500ms)
            int pause_ms = 100 + (rand() % 400);
            usleep(pause_ms * 1000);
        }
        _exit(0);
    } else if (pid > 0) {
        va_led_blink_pid = pid;
        fprintf(stderr, "[MediaPlayer] LED: processing (pulsing blue, pid=%d)\n", pid);
    }
}

// Turn off LED
static void va_led_off(void) {
    va_led_stop_blink();
    system("led off");
    fprintf(stderr, "[MediaPlayer] LED: off\n");
}

#endif // ENABLE_WAKE_WORD

// =============================================================================
// Volume Control Functions
// =============================================================================

static bool set_system_volume(float volume) {
    if (volume < 0.0f) volume = 0.0f;
    if (volume > 1.0f) volume = 1.0f;

    // IAD volume range: -30 (mute) to 120 (max gain)
    // Range is 150 units total
    // Map 0.0-1.0 to -30 to 120
    int iad_volume = (int)(-30.0f + (volume * 150.0f));
    if (iad_volume < -30) iad_volume = -30;
    if (iad_volume > 120) iad_volume = 120;

    // Send volume command to IAD via control socket
    char command[64];
    char response[256];
    snprintf(command, sizeof(command), "SET aoVol %d", iad_volume);

    int ret = iac_send_control_command(command, response, sizeof(response));
    if (ret != 0) {
        fprintf(stderr, "[MediaPlayer] Failed to set volume via IAD: %d\n", ret);
        return false;
    }

    pthread_mutex_lock(&g_player_ctx.lock);
    g_player_ctx.volume = volume;
    pthread_mutex_unlock(&g_player_ctx.lock);

    printf("[MediaPlayer] Volume set to %.2f (IAD: %d)\n", volume, iad_volume);
    return true;
}

static float get_system_volume(void) {
    pthread_mutex_lock(&g_player_ctx.lock);
    float vol = g_player_ctx.volume;
    pthread_mutex_unlock(&g_player_ctx.lock);
    return vol;
}

// =============================================================================
// Audio Streaming Functions
// =============================================================================

#define WAV_HEADER_SIZE	78
typedef struct {
    int sockfd;
    size_t bytes_received;
} curl_write_ctx_t;

static size_t curl_write_to_iad(void *buffer, size_t size, size_t nmemb, void *userp) {
    curl_write_ctx_t *ctx = (curl_write_ctx_t *)userp;
    size_t total_size = size * nmemb;
    size_t skip_bytes = 0;
    ssize_t written = 0;

    if (ctx->bytes_received < WAV_HEADER_SIZE) {
        size_t needed = WAV_HEADER_SIZE - ctx->bytes_received;
        if (total_size < needed) {
            ctx->bytes_received += total_size;
            return total_size;
        }
        skip_bytes = needed;
    }

    if ((total_size - skip_bytes) > 0) {
        written = write(ctx->sockfd, ((uint8_t *)buffer) + skip_bytes, total_size - skip_bytes);
        if (written < 0) {
            perror("[MediaPlayer] write to IAD socket");
            return 0;
        }
    }
    ctx->bytes_received += (written + skip_bytes);
    return written + skip_bytes;
}

void *audio_streaming_thread(void *arg) {
    char *url = (char *)arg;

    printf("[MediaPlayer] Starting playback of %s\n", url);

#ifdef ENABLE_WAKE_WORD
    // Suspend wake word detection during playback to avoid false triggers
    suspend_wake_word();
#endif

    int audio_sock = iac_connect_audio_output();
    if (audio_sock < 0) {
        fprintf(stderr, "[MediaPlayer] Failed to connect to IAD\n");
        free(url);
        pthread_mutex_lock(&g_player_ctx.lock);
        g_player_ctx.state = MEDIA_PLAYER_STATE_IDLE;
        g_player_ctx.playback_active = false;
        pthread_mutex_unlock(&g_player_ctx.lock);
        report_media_player_state(MEDIA_PLAYER_STATE_IDLE, g_player_ctx.volume, g_player_ctx.muted);
#ifdef ENABLE_WAKE_WORD
        // Resume wake word detection after playback error
        resume_wake_word();
#endif
        return NULL;
    }

    pthread_mutex_lock(&g_player_ctx.lock);
    g_player_ctx.audio_sock = audio_sock;
    // Note: Use PLAYING instead of ANNOUNCING because Home Assistant's ESPHome
    // integration doesn't map ANNOUNCING state (causes KeyError in HA)
    g_player_ctx.state = MEDIA_PLAYER_STATE_PLAYING;
    pthread_mutex_unlock(&g_player_ctx.lock);

    report_media_player_state(g_player_ctx.state, g_player_ctx.volume, g_player_ctx.muted);

    CURL *curl = curl_easy_init();
    if (curl) {
        curl_write_ctx_t curl_write_ctx = {
            .sockfd = audio_sock,
            .bytes_received = 0
        };
        curl_easy_setopt(curl, CURLOPT_URL, url);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_to_iad);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &curl_write_ctx);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 300L);

        CURLcode res = curl_easy_perform(curl);

        if (res != CURLE_OK) {
            fprintf(stderr, "[MediaPlayer] CURL error: %s\n", curl_easy_strerror(res));
        } else {
            printf("[MediaPlayer] Playback completed successfully\n");
        }

        curl_easy_cleanup(curl);
    }

    close(audio_sock);
    free(url);

    pthread_mutex_lock(&g_player_ctx.lock);
    g_player_ctx.audio_sock = -1;
    g_player_ctx.state = MEDIA_PLAYER_STATE_IDLE;
    g_player_ctx.playback_active = false;
    if (g_player_ctx.current_url) {
        free(g_player_ctx.current_url);
        g_player_ctx.current_url = NULL;
    }
    pthread_mutex_unlock(&g_player_ctx.lock);

    report_media_player_state(MEDIA_PLAYER_STATE_IDLE, g_player_ctx.volume, g_player_ctx.muted);

#ifdef ENABLE_WAKE_WORD
    // Resume wake word detection after playback completes
    resume_wake_word();
#endif

    return NULL;
}

static bool download_and_stream_audio(const char *url, bool is_announcement) {
    stop_current_playback();

    char *url_copy = strdup(url);
    if (!url_copy) {
        perror("[MediaPlayer] strdup");
        return false;
    }

    pthread_mutex_lock(&g_player_ctx.lock);
    g_player_ctx.playback_active = true;
    g_player_ctx.is_announcement = is_announcement;
    if (g_player_ctx.current_url) {
        free(g_player_ctx.current_url);
    }
    g_player_ctx.current_url = strdup(url);
    pthread_mutex_unlock(&g_player_ctx.lock);

    if (pthread_create(&g_player_ctx.playback_thread, NULL, audio_streaming_thread, url_copy) != 0) {
        perror("[MediaPlayer] pthread_create");
        free(url_copy);
        pthread_mutex_lock(&g_player_ctx.lock);
        g_player_ctx.playback_active = false;
        pthread_mutex_unlock(&g_player_ctx.lock);
        return false;
    }

    pthread_detach(g_player_ctx.playback_thread);
    return true;
}

static void stop_current_playback(void) {
    pthread_mutex_lock(&g_player_ctx.lock);

    if (g_player_ctx.playback_active && g_player_ctx.audio_sock >= 0) {
        printf("[MediaPlayer] Stopping current playback\n");
        close(g_player_ctx.audio_sock);
        g_player_ctx.audio_sock = -1;
        g_player_ctx.playback_active = false;
        g_player_ctx.state = MEDIA_PLAYER_STATE_IDLE;
    }

    pthread_mutex_unlock(&g_player_ctx.lock);
}

// =============================================================================
// ESPHome Plugin Callbacks
// =============================================================================

// Helper function to run TTS via system 'tell' command
static void run_tts_announcement(const char *text) {
    if (!text || !text[0]) {
        printf("[MediaPlayer] Empty TTS text, skipping\n");
        return;
    }

    // Build command: /sbin/tell "text"
    // Escape double quotes in the text
    char escaped_text[512];
    size_t j = 0;
    for (size_t i = 0; text[i] && j < sizeof(escaped_text) - 2; i++) {
        if (text[i] == '"' || text[i] == '\\') {
            escaped_text[j++] = '\\';
        }
        escaped_text[j++] = text[i];
    }
    escaped_text[j] = '\0';

    char command[640];
    snprintf(command, sizeof(command), "/sbin/tell \"%s\"", escaped_text);

    printf("[MediaPlayer] Running TTS: %s\n", command);
    int ret = system(command);
    if (ret != 0) {
        fprintf(stderr, "[MediaPlayer] TTS command failed with code %d\n", ret);
    }
}

int media_player_handle_message(esphome_plugin_context_t *ctx,
                                 int client_id,
                                 uint32_t msg_type,
                                 const uint8_t *data,
                                 size_t len) {
    // Update stored context with valid one from plugin manager
    // This ensures we always have a valid server pointer
    g_player_ctx.plugin_ctx = ctx;

#ifdef ENABLE_WAKE_WORD
    if (msg_type == ESPHOME_MSG_SWITCH_COMMAND_REQUEST) {
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Received SWITCH_COMMAND_REQUEST");
        switch_command_request_t cmd_msg;
        if (!switch_decode_command_request(data, len, &cmd_msg)) {
            esphome_plugin_log(ctx, 0, "[MediaPlayer] Failed to decode switch command");
            return -1;
        }
        if(cmd_msg.key == wake_word_switch_key && wake_word_is_available()) {
            if(cmd_msg.state && g_wake_word_suspended) {
                esphome_plugin_log(ctx, 2, "[MediaPlayer] Resume wake word detection");
                resume_wake_word();
            }
            else if(!cmd_msg.state && !g_wake_word_suspended) {
                esphome_plugin_log(ctx, 2, "[MediaPlayer] Suspend wake word detection");
                suspend_wake_word();
            }
            report_switch_state(wake_word_switch_key, !g_wake_word_suspended);
        }
        return 0;
    }
#endif

    // Handle Voice Assistant Subscribe Request (94)
    if (msg_type == ESPHOME_MSG_SUBSCRIBE_VOICE_ASSISTANT_REQUEST) {
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Received SUBSCRIBE_VOICE_ASSISTANT_REQUEST");
        // We don't need to send a response - just acknowledge we support it
        // The device info already advertises our voice assistant features
        return 0;
    }

    // Handle Voice Assistant Configuration Request (101)
    if (msg_type == ESPHOME_MSG_VOICE_ASSISTANT_CONFIGURATION_REQUEST) {
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Received VOICE_ASSISTANT_CONFIGURATION_REQUEST");

        // Send VoiceAssistantConfigurationResponse (102)
        // Fields:
        //   1: repeated VoiceAssistantWakeWord available_wake_words
        //   2: repeated string active_wake_words
        //   3: uint32 max_active_wake_words
        uint8_t response_buf[64];
        pb_buffer_t pb;
        pb_buffer_init_write(&pb, response_buf, sizeof(response_buf));

#ifdef ENABLE_WAKE_WORD
        // If wake word is available, advertise it
        if (wake_word_is_available()) {
            // Field 3: max_active_wake_words = 1
            pb_encode_uint32(&pb, 3, 1);
        } else {
            pb_encode_uint32(&pb, 3, 0);
        }
#else
        // Field 3: max_active_wake_words = 0 (no wake word support on device)
        pb_encode_uint32(&pb, 3, 0);
#endif

        if (!pb.error && pb.pos > 0) {
            esphome_plugin_send_message(ctx,
                                         ESPHOME_MSG_VOICE_ASSISTANT_CONFIGURATION_RESPONSE,
                                         response_buf, pb.pos);
            esphome_plugin_log(ctx, 2, "[MediaPlayer] Sent VOICE_ASSISTANT_CONFIGURATION_RESPONSE");
        }
        return 0;
    }

    // Handle Voice Assistant Response (37) - HA responds to our VoiceAssistantRequest
    if (msg_type == ESPHOME_MSG_VOICE_ASSISTANT_RESPONSE) {
        // Fields:
        //   1: uint32 port (UDP port to stream audio to)
        //   2: bool error (if true, an error occurred)
        uint32_t port = 0;
        bool error = false;

        pb_buffer_t pb;
        pb_buffer_init_read(&pb, data, len);

        while (pb.pos < pb.size && !pb.error) {
            uint64_t tag_value;
            if (!pb_decode_varint(&pb, &tag_value)) break;

            uint32_t field_num = tag_value >> 3;
            uint8_t wire_type = tag_value & 0x07;

            switch (field_num) {
                case 1: // port
                    if (wire_type == PB_WIRE_TYPE_VARINT) {
                        uint64_t val;
                        pb_decode_varint(&pb, &val);
                        port = (uint32_t)val;
                    } else {
                        pb_skip_field(&pb, wire_type);
                    }
                    break;
                case 2: // error
                    if (wire_type == PB_WIRE_TYPE_VARINT) {
                        uint64_t val;
                        pb_decode_varint(&pb, &val);
                        error = val != 0;
                    } else {
                        pb_skip_field(&pb, wire_type);
                    }
                    break;
                default:
                    pb_skip_field(&pb, wire_type);
                    break;
            }
        }

        if (error) {
            esphome_plugin_log(ctx, 1, "[MediaPlayer] VoiceAssistantResponse: error");
#ifdef ENABLE_WAKE_WORD
            stop_ha_audio_stream();
#endif
        } else if (port > 0) {
            esphome_plugin_log(ctx, 2, "[MediaPlayer] VoiceAssistantResponse: stream to UDP port %u", port);
#ifdef ENABLE_WAKE_WORD
            // Get the client host address from the plugin context
            char ha_host[64] = "127.0.0.1";
            if (esphome_plugin_get_client_host(ctx, client_id, ha_host, sizeof(ha_host)) != 0) {
                esphome_plugin_log(ctx, 1, "[MediaPlayer] Failed to get client host, using fallback");
            }
            if (start_ha_audio_stream(ha_host, port) != 0) {
                esphome_plugin_log(ctx, 0, "[MediaPlayer] Failed to start UDP audio stream");
            }
#endif
        } else {
            // port == 0 means stream via API (VOICE_ASSISTANT_AUDIO messages)
            esphome_plugin_log(ctx, 2, "[MediaPlayer] VoiceAssistantResponse: stream via API");
#ifdef ENABLE_WAKE_WORD
            if (start_ha_api_audio_stream(client_id) != 0) {
                esphome_plugin_log(ctx, 0, "[MediaPlayer] Failed to start API audio stream");
            }
#endif
        }

        return 0;
    }

    // Handle Voice Assistant Event Response (92)
    if (msg_type == ESPHOME_MSG_VOICE_ASSISTANT_EVENT_RESPONSE) {
        // Decode event type and data
        // Fields:
        //   1: VoiceAssistantEventType event_type
        //   2: repeated VoiceAssistantEventData data (key-value pairs)
        //      VoiceAssistantEventData:
        //        1: string name
        //        2: string value
        uint32_t event_type = 0;
        char tts_url[512] = {0};

        pb_buffer_t pb;
        pb_buffer_init_read(&pb, data, len);

        while (pb.pos < pb.size && !pb.error) {
            uint64_t tag_value;
            if (!pb_decode_varint(&pb, &tag_value)) break;

            uint32_t field_num = tag_value >> 3;
            uint8_t wire_type = tag_value & 0x07;

            switch (field_num) {
                case 1: // event_type
                    if (wire_type == PB_WIRE_TYPE_VARINT) {
                        uint64_t val;
                        pb_decode_varint(&pb, &val);
                        event_type = (uint32_t)val;
                    } else {
                        pb_skip_field(&pb, wire_type);
                    }
                    break;
                case 2: // data (repeated VoiceAssistantEventData)
                    if (wire_type == PB_WIRE_TYPE_LENGTH) {
                        // Get submessage length
                        uint64_t sub_len;
                        pb_decode_varint(&pb, &sub_len);
                        size_t sub_end = pb.pos + sub_len;

                        char key[64] = {0};
                        char value[512] = {0};

                        // Parse the submessage
                        while (pb.pos < sub_end && !pb.error) {
                            uint64_t sub_tag;
                            if (!pb_decode_varint(&pb, &sub_tag)) break;

                            uint32_t sub_field = sub_tag >> 3;
                            uint8_t sub_wire = sub_tag & 0x07;

                            switch (sub_field) {
                                case 1: // name
                                    if (sub_wire == PB_WIRE_TYPE_LENGTH) {
                                        pb_decode_string(&pb, key, sizeof(key));
                                    } else {
                                        pb_skip_field(&pb, sub_wire);
                                    }
                                    break;
                                case 2: // value
                                    if (sub_wire == PB_WIRE_TYPE_LENGTH) {
                                        pb_decode_string(&pb, value, sizeof(value));
                                    } else {
                                        pb_skip_field(&pb, sub_wire);
                                    }
                                    break;
                                default:
                                    pb_skip_field(&pb, sub_wire);
                                    break;
                            }
                        }

                        // Check if this is the URL we're looking for
                        if (strcmp(key, "url") == 0 && value[0] != '\0') {
                            strncpy(tts_url, value, sizeof(tts_url) - 1);
                        }
                    } else {
                        pb_skip_field(&pb, wire_type);
                    }
                    break;
                default:
                    pb_skip_field(&pb, wire_type);
                    break;
            }
        }

        // Log the event type
        // Event types from ESPHome api.proto:
        // 0 = VOICE_ASSISTANT_ERROR
        // 1 = VOICE_ASSISTANT_RUN_START
        // 2 = VOICE_ASSISTANT_RUN_END
        // 3 = VOICE_ASSISTANT_STT_START
        // 4 = VOICE_ASSISTANT_STT_END
        // 5 = VOICE_ASSISTANT_INTENT_START
        // 6 = VOICE_ASSISTANT_INTENT_END
        // 7 = VOICE_ASSISTANT_TTS_START
        // 8 = VOICE_ASSISTANT_TTS_END
        // 9 = VOICE_ASSISTANT_WAKE_WORD_START
        // 10 = VOICE_ASSISTANT_WAKE_WORD_END
        // 11 = VOICE_ASSISTANT_STT_VAD_START
        // 12 = VOICE_ASSISTANT_STT_VAD_END
        // 13 = VOICE_ASSISTANT_TTS_STREAM_START
        // 14 = VOICE_ASSISTANT_TTS_STREAM_END
        const char *event_names[] = {
            "ERROR", "RUN_START", "RUN_END", "STT_START", "STT_END",
            "INTENT_START", "INTENT_END", "TTS_START", "TTS_END",
            "WAKE_WORD_START", "WAKE_WORD_END", "STT_VAD_START", "STT_VAD_END",
            "TTS_STREAM_START", "TTS_STREAM_END"
        };
        const char *event_name = (event_type < 15) ? event_names[event_type] : "UNKNOWN";

        esphome_plugin_log(ctx, 2, "[MediaPlayer] VoiceAssistantEvent: %s (%u)", event_name, event_type);

        // Handle specific events
        switch (event_type) {
            case 0: // ERROR
                esphome_plugin_log(ctx, 1, "[MediaPlayer] Voice assistant error occurred");
#ifdef ENABLE_WAKE_WORD
                stop_ha_audio_stream();
                va_led_off();
                // Note: stop_ha_audio_stream() already calls resume_wake_word()
#endif
                break;
            case 2: // RUN_END
                // Pipeline ended, stop streaming
                esphome_plugin_log(ctx, 2, "[MediaPlayer] Voice pipeline ended");
#ifdef ENABLE_WAKE_WORD
                stop_ha_audio_stream();
                va_led_off();
#endif
                break;
            case 4: // STT_END
                // Speech-to-text finished, can stop streaming audio
                // Don't resume wake word yet - TTS playback will follow and resume it when done
                esphome_plugin_log(ctx, 2, "[MediaPlayer] STT finished, stopping audio stream");
#ifdef ENABLE_WAKE_WORD
                stop_ha_audio_stream_internal(false);  // Don't resume wake word yet
                // Switch to blinking while processing intent/TTS
                va_led_processing();
#endif
                break;
            case 8: // TTS_END
                // Text-to-speech finished, play the audio if URL provided
                if (tts_url[0] != '\0') {
                    esphome_plugin_log(ctx, 2, "[MediaPlayer] TTS_END with URL: %s", tts_url);
                    // Play the TTS audio as an announcement
                    download_and_stream_audio(tts_url, true);
                }
                break;
            default:
                break;
        }

        return 0;
    }

    // Handle Voice Assistant Announce Request (119)
    if (msg_type == ESPHOME_MSG_VOICE_ASSISTANT_ANNOUNCE_REQUEST) {
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Received VOICE_ASSISTANT_ANNOUNCE_REQUEST");

        // Decode the announce request
        // Fields:
        //   1: string media_id (URL)
        //   2: string text (TTS text)
        //   3: bool start_conversation
        //   4: string preannounce_media_id
        char media_id[512] = {0};
        char text[512] = {0};

        pb_buffer_t pb;
        pb_buffer_init_read(&pb, data, len);

        while (pb.pos < pb.size && !pb.error) {
            uint64_t tag_value;
            if (!pb_decode_varint(&pb, &tag_value)) break;

            uint32_t field_num = tag_value >> 3;
            uint8_t wire_type = tag_value & 0x07;

            switch (field_num) {
                case 1: // media_id
                    if (wire_type == PB_WIRE_TYPE_LENGTH) {
                        pb_decode_string(&pb, media_id, sizeof(media_id));
                    } else {
                        pb_skip_field(&pb, wire_type);
                    }
                    break;
                case 2: // text
                    if (wire_type == PB_WIRE_TYPE_LENGTH) {
                        pb_decode_string(&pb, text, sizeof(text));
                    } else {
                        pb_skip_field(&pb, wire_type);
                    }
                    break;
                default:
                    pb_skip_field(&pb, wire_type);
                    break;
            }
        }

        esphome_plugin_log(ctx, 2, "[MediaPlayer] Announcement: media_id=%s, text=%s",
                           media_id[0] ? media_id : "(none)", text[0] ? text : "(none)");

        // Prefer media_id (pre-generated TTS audio from Home Assistant) over local TTS
        if (media_id[0]) {
            // Play the TTS audio URL from Home Assistant
            download_and_stream_audio(media_id, true);
        } else if (text[0]) {
            // Fall back to local TTS via 'tell' command
            run_tts_announcement(text);
        }

        // Send VoiceAssistantAnnounceFinished (100)
        // Fields:
        //   1: bool success
        uint8_t response_buf[16];
        pb_buffer_t resp_pb;
        pb_buffer_init_write(&resp_pb, response_buf, sizeof(response_buf));
        pb_encode_bool(&resp_pb, 1, true); // success = true

        if (!resp_pb.error && resp_pb.pos > 0) {
            esphome_plugin_send_message(ctx,
                                         ESPHOME_MSG_VOICE_ASSISTANT_ANNOUNCE_FINISHED,
                                         response_buf, resp_pb.pos);
            esphome_plugin_log(ctx, 2, "[MediaPlayer] Sent VOICE_ASSISTANT_ANNOUNCE_FINISHED");
        }
        return 0;
    }

    if (msg_type != ESPHOME_MSG_MEDIA_PLAYER_COMMAND_REQUEST) {
        return -1; // Not our message
    }

    media_player_command_request_t cmd_msg;
    if (!media_player_decode_command_request(data, len, &cmd_msg)) {
        esphome_plugin_log(ctx, 0, "[MediaPlayer] Failed to decode command");
        return -1;
    }

    if (cmd_msg.key != media_player_key) {
        return -1; // Not for us
    }

    if (cmd_msg.has_media_url && cmd_msg.media_url[0]) {
        bool is_announcement = cmd_msg.has_announcement && cmd_msg.announcement;
        download_and_stream_audio(cmd_msg.media_url, is_announcement);
    }

    if (cmd_msg.has_command) {
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Received command: %d", cmd_msg.command);

        switch (cmd_msg.command) {
            case MEDIA_PLAYER_COMMAND_PLAY:
                pthread_mutex_lock(&g_player_ctx.lock);
                g_player_ctx.state = MEDIA_PLAYER_STATE_PLAYING;
                pthread_mutex_unlock(&g_player_ctx.lock);
                report_media_player_state(MEDIA_PLAYER_STATE_PLAYING, g_player_ctx.volume, g_player_ctx.muted);
                break;

            case MEDIA_PLAYER_COMMAND_PAUSE:
                pthread_mutex_lock(&g_player_ctx.lock);
                g_player_ctx.state = MEDIA_PLAYER_STATE_PAUSED;
                pthread_mutex_unlock(&g_player_ctx.lock);
                report_media_player_state(MEDIA_PLAYER_STATE_PAUSED, g_player_ctx.volume, g_player_ctx.muted);
                break;

            case MEDIA_PLAYER_COMMAND_STOP:
                stop_current_playback();
                report_media_player_state(MEDIA_PLAYER_STATE_IDLE, g_player_ctx.volume, g_player_ctx.muted);
                break;

            case MEDIA_PLAYER_COMMAND_MUTE:
                {
                    char response[256];
                    iac_send_control_command("SET aoMute 1", response, sizeof(response));
                    pthread_mutex_lock(&g_player_ctx.lock);
                    g_player_ctx.muted = true;
                    pthread_mutex_unlock(&g_player_ctx.lock);
                    report_media_player_state(g_player_ctx.state, g_player_ctx.volume, true);
                }
                break;

            case MEDIA_PLAYER_COMMAND_UNMUTE:
                {
                    char response[256];
                    iac_send_control_command("SET aoMute 0", response, sizeof(response));
                    pthread_mutex_lock(&g_player_ctx.lock);
                    g_player_ctx.muted = false;
                    float vol = g_player_ctx.volume;
                    pthread_mutex_unlock(&g_player_ctx.lock);
                    report_media_player_state(g_player_ctx.state, vol, false);
                }
                break;

            case MEDIA_PLAYER_COMMAND_VOLUME_UP:
                {
                    float current_vol = get_system_volume();
                    float new_vol = current_vol + 0.1f;
                    if (new_vol > 1.0f) new_vol = 1.0f;
                    set_system_volume(new_vol);
                    report_media_player_state(g_player_ctx.state, new_vol, g_player_ctx.muted);
                }
                break;

            case MEDIA_PLAYER_COMMAND_VOLUME_DOWN:
                {
                    float current_vol = get_system_volume();
                    float new_vol = current_vol - 0.1f;
                    if (new_vol < 0.0f) new_vol = 0.0f;
                    set_system_volume(new_vol);
                    report_media_player_state(g_player_ctx.state, new_vol, g_player_ctx.muted);
                }
                break;

            default:
                break;
        }
    }

    if (cmd_msg.has_volume) {
        set_system_volume(cmd_msg.volume);
        report_media_player_state(g_player_ctx.state, cmd_msg.volume, g_player_ctx.muted);
    }

    return 0; // Handled
}

int media_player_list_entities(esphome_plugin_context_t *ctx, int client_id) {
    list_entities_media_player_response_t entity = {
        .object_id = "speaker",
        .key = media_player_key,
        .name = "Thingino Speaker",
        .icon = "mdi:speaker",
        .disabled_by_default = false,
        .entity_category = 0,
        .supports_pause = false, // IAD doesn't support pause
        .formats = (media_player_supported_format_t *)supported_formats,  // Already correct type
        .formats_count = sizeof(supported_formats) / sizeof(supported_formats[0]),
        .feature_flags = MEDIA_PLAYER_FEATURE_VOLUME_SET |
                         MEDIA_PLAYER_FEATURE_VOLUME_MUTE |
                         MEDIA_PLAYER_FEATURE_TURN_ON |
                         MEDIA_PLAYER_FEATURE_TURN_OFF |
                         MEDIA_PLAYER_FEATURE_PLAY_MEDIA |
                         MEDIA_PLAYER_FEATURE_VOLUME_STEP |
                         MEDIA_PLAYER_FEATURE_STOP |
						 MEDIA_PLAYER_FEATURE_BROWSE_MEDIA |
                         MEDIA_PLAYER_FEATURE_MEDIA_ANNOUNCE
    };

    uint8_t encode_buf[512];
    size_t len = media_player_encode_list_entities_response(encode_buf, sizeof(encode_buf), &entity);

    if (len > 0) {
        esphome_plugin_send_message_to_client(ctx, client_id,
                                               ESPHOME_MSG_LIST_ENTITIES_MEDIA_PLAYER_RESPONSE,
                                               encode_buf, len);
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Sent entity list response");
    } else {
        esphome_plugin_log(ctx, 0, "[MediaPlayer] Failed to encode entity list");
        return -1;
    }
#ifdef ENABLE_WAKE_WORD
    list_entities_switch_response_t switch_entity = {
        .object_id = "speaker",
        .key = wake_word_switch_key,
        .name = "Listen for Wake-word",
        .icon = "mdi:microphone",
        .assumed_state = false,
        .disabled_by_default = false,
        .entity_category = 0,
        .device_class = ""
    };

    len = switch_encode_list_entities_response(encode_buf, sizeof(encode_buf), &switch_entity);
    if (len > 0) {
        esphome_plugin_send_message_to_client(ctx, client_id,
                                               ESPHOME_MSG_LIST_ENTITIES_SWITCH_RESPONSE,
                                               encode_buf, len);
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Sent switch entity list response");
    } else {
        esphome_plugin_log(ctx, 0, "[MediaPlayer] Failed to encode switch entity list");
        return -1;
    }
#endif
    return 0;
}

#ifdef ENABLE_WAKE_WORD
// =============================================================================
// Wake Word Detection Callback
// =============================================================================

static void wake_word_detected_callback(float probability, void *userdata) {
    (void)userdata;

    if (!g_player_ctx.plugin_ctx) {
        fprintf(stderr, "[MediaPlayer] Wake word detected but no plugin context\n");
        return;
    }

    esphome_plugin_log(g_player_ctx.plugin_ctx, 2,
                       "[MediaPlayer] Wake word detected (probability: %.2f)", probability);

    // Turn on LED to indicate listening
    va_led_listening();

    // Send VoiceAssistantRequest (36) to Home Assistant
    // This tells HA to start the voice pipeline
    // Fields:
    //   1: bool start = true (start listening)
    //   2: string conversation_id (optional)
    //   3: uint32 flags (optional)
    //   4: VoiceAssistantAudioSettings audio_settings (optional)
    //   5: string wake_word_phrase (optional)
    uint8_t request_buf[64];
    pb_buffer_t pb;
    pb_buffer_init_write(&pb, request_buf, sizeof(request_buf));

    // Field 1: start = true
    pb_encode_bool(&pb, 1, true);

    // Field 3: flags = 0 (no special flags for now)
    // Could use VOICE_ASSISTANT_REQUEST_USE_WAKE_WORD (1<<2) etc.
    pb_encode_uint32(&pb, 3, 0);

    if (!pb.error && pb.pos > 0) {
        esphome_plugin_send_message(g_player_ctx.plugin_ctx,
                                     ESPHOME_MSG_VOICE_ASSISTANT_REQUEST,
                                     request_buf, pb.pos);
        esphome_plugin_log(g_player_ctx.plugin_ctx, 2,
                           "[MediaPlayer] Sent VOICE_ASSISTANT_REQUEST to start pipeline");
    } else {
        esphome_plugin_log(g_player_ctx.plugin_ctx, 0,
                           "[MediaPlayer] Failed to encode VoiceAssistantRequest");
    }
}
#endif

int media_player_init(esphome_plugin_context_t *ctx) {
    esphome_plugin_log(ctx, 2, "[%s] Initializing version %s", plugin_name, plugin_version);

    // Store plugin context
    g_player_ctx.plugin_ctx = ctx;

    // Reset shutdown flag and register atexit handler
    g_shutdown_requested = false;
    register_shutdown_handlers();

    // Initialize mutex
    pthread_mutex_init(&g_player_ctx.lock, NULL);

    // Initialize CURL
    curl_global_init(CURL_GLOBAL_DEFAULT);

    // Check if IAD is available
    if (!iac_check_output_available()) {
        esphome_plugin_log(ctx, 1, "[MediaPlayer] WARNING: IAD not available");
    }

    // Set initial volume
    set_system_volume(g_player_ctx.volume);

#ifdef ENABLE_WAKE_WORD
    // Initialize wake word detection
    if (wake_word_init(ctx, NULL, wake_word_detected_callback, NULL) == 0) {
        esphome_plugin_log(ctx, 2, "[MediaPlayer] Wake word detection initialized");
        // Start wake word detection
        if (wake_word_start() == 0) {
            esphome_plugin_log(ctx, 2, "[MediaPlayer] Wake word detection started");
        } else {
            esphome_plugin_log(ctx, 1, "[MediaPlayer] Failed to start wake word detection");
        }
    } else {
        esphome_plugin_log(ctx, 1, "[MediaPlayer] Wake word detection not available (no model?)");
    }
#endif

    esphome_plugin_log(ctx, 2, "[MediaPlayer] Initialized successfully");
    return 0;
}

void media_player_cleanup(esphome_plugin_context_t *ctx) {
    esphome_plugin_log(ctx, 2, "[%s] Cleaning up", plugin_name);

    // Signal shutdown to unblock any waiting operations
    g_shutdown_requested = true;

    stop_current_playback();
#ifdef ENABLE_WAKE_WORD
    stop_ha_audio_stream();
    va_led_off();  // Turn off LED during cleanup
    wake_word_cleanup();
#endif
    curl_global_cleanup();
    pthread_mutex_destroy(&g_player_ctx.lock);

    if (g_player_ctx.current_url) {
        free(g_player_ctx.current_url);
        g_player_ctx.current_url = NULL;
    }

    esphome_plugin_log(ctx, 2, "[MediaPlayer] Cleanup complete");
}

int media_player_subscribe_states(esphome_plugin_context_t *ctx, int client_id) {
    // Store plugin context
    g_player_ctx.plugin_ctx = ctx;

    report_media_player_state(g_player_ctx.state, g_player_ctx.volume, g_player_ctx.muted);
#ifdef ENABLE_WAKE_WORD
    report_switch_state(wake_word_switch_key, !g_wake_word_suspended);
#endif
    return 0;
}

int media_player_configure_device_info(esphome_plugin_context_t *ctx,
                                        esphome_device_info_response_t *device_info) {
    (void)ctx;

	// Set the webserver_port since we expose a web server
	device_info->webserver_port = 80;

    // Enable Voice Assistant features since we have a media player for TTS output
    // We support announcements via the media player (no direct speaker streaming)
    device_info->voice_assistant_feature_flags |=
        VOICE_ASSISTANT_FEATURE_VOICE_ASSISTANT |  // Basic voice assistant support
        VOICE_ASSISTANT_FEATURE_ANNOUNCE |         // Announcement support (TTS via media player)
        VOICE_ASSISTANT_FEATURE_TIMERS |           // Timer support
        VOICE_ASSISTANT_FEATURE_START_CONVERSATION; // Start conversation support

#ifdef ENABLE_WAKE_WORD
    // Add on-device wake word support if available
    if (wake_word_is_available()) {
        device_info->voice_assistant_feature_flags |=
            VOICE_ASSISTANT_FEATURE_API_AUDIO;  // We can stream audio to HA
        // Note: We handle wake word detection ourselves, so we don't set
        // VOICE_ASSISTANT_FEATURE_API_WAKE_WORD_STREAMING
    }
#endif

    // Note: We do NOT set VOICE_ASSISTANT_FEATURE_SPEAKER because we use the media player
    // for TTS output rather than direct audio streaming

    printf("[MediaPlayer] Configured voice assistant features: 0x%x\n",
           device_info->voice_assistant_feature_flags);

    return 0;
}

// Register plugin with ESPHome
ESPHOME_PLUGIN_REGISTER(thingino_media_player_plugin,
                         "ThinginoMediaPlayer",
                         "1.0.0",
                         media_player_init,
                         media_player_cleanup,
                         media_player_handle_message,
                         media_player_configure_device_info,  // Set voice assistant feature flags
                         media_player_list_entities,
						 media_player_subscribe_states
);