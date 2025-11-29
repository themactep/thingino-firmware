#ifndef THINGINO_MEDIA_PLAYER_H
#define THINGINO_MEDIA_PLAYER_H

#include <stdint.h>
#include <stdbool.h>
#include <pthread.h>
#include "esphome_plugin.h"

#ifdef __cplusplus
extern "C" {
#endif

// IAC (Ingenic Audio Client) socket paths
#define AUDIO_INPUT_SOCKET_PATH "ingenic_audio_input"
#define AUDIO_OUTPUT_SOCKET_PATH "ingenic_audio_output"
#define AUDIO_CONTROL_SOCKET_PATH "ingenic_audio_control"

// Audio socket request types
#define AUDIO_INPUT_REQUEST 1
#define AUDIO_OUTPUT_REQUEST 2

#ifdef ENABLE_WAKE_WORD
// Audio input configuration (from IAD)
#define AUDIO_INPUT_SAMPLE_RATE 16000
#define AUDIO_INPUT_CHANNELS 1
#define AUDIO_INPUT_BITS_PER_SAMPLE 16
#define AUDIO_INPUT_BUFFER_SIZE 4096
#endif

// ESPHome MediaPlayer feature flags (from MediaPlayerEntityFeature enum)
#define MEDIA_PLAYER_FEATURE_PAUSE          (1 << 0)
#define MEDIA_PLAYER_FEATURE_SEEK           (1 << 1)
#define MEDIA_PLAYER_FEATURE_VOLUME_SET     (1 << 2)
#define MEDIA_PLAYER_FEATURE_VOLUME_MUTE    (1 << 3)
#define MEDIA_PLAYER_FEATURE_PREVIOUS_TRACK (1 << 4)
#define MEDIA_PLAYER_FEATURE_NEXT_TRACK     (1 << 5)
#define MEDIA_PLAYER_FEATURE_TURN_ON        (1 << 7)
#define MEDIA_PLAYER_FEATURE_TURN_OFF       (1 << 8)
#define MEDIA_PLAYER_FEATURE_PLAY_MEDIA     (1 << 9)
#define MEDIA_PLAYER_FEATURE_VOLUME_STEP    (1 << 10)
#define MEDIA_PLAYER_FEATURE_SELECT_SOURCE  (1 << 11)
#define MEDIA_PLAYER_FEATURE_STOP           (1 << 12)
#define MEDIA_PLAYER_FEATURE_CLEAR_PLAYLIST (1 << 13)
#define MEDIA_PLAYER_FEATURE_PLAY           (1 << 14)
#define MEDIA_PLAYER_FEATURE_SHUFFLE_SET    (1 << 15)
#define MEDIA_PLAYER_FEATURE_SELECT_SOUND_MODE (1 << 16)
#define MEDIA_PLAYER_FEATURE_BROWSE_MEDIA   (1 << 17)
#define MEDIA_PLAYER_FEATURE_REPEAT_SET     (1 << 18)
#define MEDIA_PLAYER_FEATURE_GROUPING       (1 << 19)
#define MEDIA_PLAYER_FEATURE_MEDIA_ANNOUNCE (1 << 20)
#define MEDIA_PLAYER_FEATURE_MEDIA_ENQUEUE  (1 << 21)
#define MEDIA_PLAYER_FEATURE_SEARCH_MEDIA   (1 << 22)

// ESPHome MediaPlayer states (from proto)
typedef enum {
    MEDIA_PLAYER_STATE_NONE = 0,
    MEDIA_PLAYER_STATE_IDLE = 1,
    MEDIA_PLAYER_STATE_PLAYING = 2,
    MEDIA_PLAYER_STATE_PAUSED = 3,
    MEDIA_PLAYER_STATE_ANNOUNCING = 4,
    MEDIA_PLAYER_STATE_OFF = 5,
    MEDIA_PLAYER_STATE_ON = 6
} MediaPlayerState;

// ESPHome MediaPlayer commands (from proto)
typedef enum {
    MEDIA_PLAYER_COMMAND_PLAY = 0,
    MEDIA_PLAYER_COMMAND_PAUSE = 1,
    MEDIA_PLAYER_COMMAND_STOP = 2,
    MEDIA_PLAYER_COMMAND_MUTE = 3,
    MEDIA_PLAYER_COMMAND_UNMUTE = 4,
    MEDIA_PLAYER_COMMAND_TOGGLE = 5,
    MEDIA_PLAYER_COMMAND_VOLUME_UP = 6,
    MEDIA_PLAYER_COMMAND_VOLUME_DOWN = 7,
    MEDIA_PLAYER_COMMAND_ENQUEUE = 8,
    MEDIA_PLAYER_COMMAND_REPEAT_ONE = 9,
    MEDIA_PLAYER_COMMAND_REPEAT_OFF = 10,
    MEDIA_PLAYER_COMMAND_CLEAR_PLAYLIST = 11,
    MEDIA_PLAYER_COMMAND_TURN_ON = 12,
    MEDIA_PLAYER_COMMAND_TURN_OFF = 13
} MediaPlayerCommand;

// Supported audio formats
typedef struct {
    char format[16];        // "wav", "mp3", "pcm"
    uint32_t sample_rate;   // 16000, 48000, etc.
    uint32_t num_channels;  // 1 (mono), 2 (stereo)
    uint32_t sample_bytes;  // 2 (16-bit), 4 (32-bit)
} AudioFormat;

#ifdef ENABLE_WAKE_WORD
// Audio input callback function type
// Called when audio data is available from the microphone
// buffer: PCM audio data (16-bit signed, 16kHz mono)
// len: number of bytes in buffer
// userdata: user-provided context
typedef void (*audio_input_callback_t)(const int16_t *buffer, size_t samples, void *userdata);
#endif

// Media player state structure
typedef struct {
    esphome_plugin_context_t *plugin_ctx;  // ESPHome plugin context
    MediaPlayerState state;
    float volume;           // 0.0 to 1.0
    bool muted;
    pthread_mutex_t lock;

    // Playback control
    int audio_sock;         // Socket to IAD for audio data
    pthread_t playback_thread;
    bool playback_active;
    char *current_url;      // Current media URL being played
    bool is_announcement;   // True if current playback is an announcement

#ifdef ENABLE_WAKE_WORD
    // Audio input
    int audio_input_sock;   // Socket to IAD for audio input
    pthread_t audio_input_thread;
    bool audio_input_active;
    audio_input_callback_t audio_input_callback;
    void *audio_input_userdata;

    // Audio streaming to Home Assistant
    int ha_stream_sock;     // UDP socket for streaming to HA
    uint32_t ha_stream_port; // UDP port for HA streaming
    char ha_stream_host[64]; // Home Assistant host address
    pthread_t ha_stream_thread;
    bool ha_streaming_active;
    bool ha_api_streaming;  // True if streaming via API (VOICE_ASSISTANT_AUDIO), false for UDP
    int ha_stream_client_id; // Client ID for sending API audio messages
#endif
} MediaPlayerContext;

#ifdef ENABLE_WAKE_WORD
// Audio input API
int media_player_start_audio_input(audio_input_callback_t callback, void *userdata);
void media_player_stop_audio_input(void);
#endif

// Check if shutdown has been requested (for graceful thread termination)
bool media_player_is_shutdown_requested(void);

// Request shutdown - can be called from signal handlers to stop all threads
void media_player_request_shutdown(void);

// ESPHome Plugin API callbacks (must match esphome_plugin.h signatures)
int media_player_init(esphome_plugin_context_t *ctx);
void media_player_cleanup(esphome_plugin_context_t *ctx);
int media_player_handle_message(esphome_plugin_context_t *ctx, int client_id, uint32_t msg_type,
                                  const uint8_t *data, size_t len);
int media_player_list_entities(esphome_plugin_context_t *ctx, int client_id);

// Internal helper functions (static in implementation)
// These are not exposed in the header since they're internal

#ifdef __cplusplus
}
#endif

#endif // THINGINO_MEDIA_PLAYER_H
