/**
 * @file media_player_proto.h
 * @brief Protobuf encoding/decoding for ESPHome MediaPlayer messages
 *
 * These functions extend esphome_proto.h with MediaPlayer-specific messages.
 */

#ifndef MEDIA_PLAYER_PROTO_H
#define MEDIA_PLAYER_PROTO_H

#include "esphome_proto.h"
#include "thingino_media_player.h"

/**
 * MediaPlayer Command Request structure (message ID 52)
 * From api.proto MediaPlayerCommandRequest
 */
typedef struct {
    uint32_t key;               // Field 1: Entity key
    bool has_command;           // Field 2: Command present flag
    uint32_t command;           // Field 3: MediaPlayerCommand enum
    bool has_volume;            // Field 4: Volume present flag
    float volume;               // Field 5: Volume level (0.0-1.0)
    bool has_media_url;         // Field 6: Media URL present flag
    char media_url[256];        // Field 7: Media URL
    bool has_announcement;      // Field 8: Announcement flag present
    bool announcement;          // Field 9: Is announcement
} media_player_command_request_t;

/**
 * MediaPlayer State Response structure (message ID 51)
 * From api.proto MediaPlayerStateResponse
 */
typedef struct {
    uint32_t key;               // Field 1: Entity key
    uint32_t state;             // Field 2: MediaPlayerState enum
    float volume;               // Field 3: Volume level
    bool muted;                 // Field 4: Mute status
} media_player_state_response_t;

/**
 * MediaPlayer Supported Format structure
 * From api.proto MediaPlayerSupportedFormat
 */
typedef struct {
    char format[16];            // Field 1: Format name (WAV, MP3, etc.)
    uint32_t sample_rate;       // Field 2: Sample rate in Hz
    uint32_t num_channels;      // Field 3: Number of channels
    uint32_t purpose;           // Field 4: Purpose (0=default, 1=announcement)
    uint32_t sample_bytes;      // Field 5: Bytes per sample
} media_player_supported_format_t;

/**
 * List Entities MediaPlayer Response structure (message ID 63 in full API)
 * From api.proto ListEntitiesMediaPlayerResponse
 */
typedef struct {
    char object_id[64];         // Field 1: Object ID
    uint32_t key;               // Field 2: Entity key
    char name[128];             // Field 3: Display name
    char icon[64];              // Field 5: Icon
    bool disabled_by_default;   // Field 6: Disabled by default
    uint32_t entity_category;   // Field 7: Entity category
    bool supports_pause;        // Field 8: Supports pause
    media_player_supported_format_t *formats;  // Field 9: Supported formats
    size_t formats_count;       // Number of formats
    uint32_t feature_flags;     // Field 11: Feature flags
} list_entities_media_player_response_t;

/**
 * Decode MediaPlayerCommandRequest from protobuf
 *
 * @param buf Protobuf encoded data
 * @param size Size of data
 * @param msg Output structure
 * @return true on success, false on error
 */
bool media_player_decode_command_request(const uint8_t *buf, size_t size,
                                           media_player_command_request_t *msg);

/**
 * Encode MediaPlayerStateResponse to protobuf
 *
 * @param buf Output buffer
 * @param size Buffer size
 * @param msg State to encode
 * @return Number of bytes written, or 0 on error
 */
size_t media_player_encode_state_response(uint8_t *buf, size_t size,
                                            const media_player_state_response_t *msg);

/**
 * Encode ListEntitiesMediaPlayerResponse to protobuf
 *
 * @param buf Output buffer
 * @param size Buffer size
 * @param msg Entity info to encode
 * @return Number of bytes written, or 0 on error
 */
size_t media_player_encode_list_entities_response(uint8_t *buf, size_t size,
                                                    const list_entities_media_player_response_t *msg);

#endif /* MEDIA_PLAYER_PROTO_H */
