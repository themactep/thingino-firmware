/**
 * @file media_player_proto.c
 * @brief Protobuf encoding/decoding implementation for MediaPlayer messages
 */

#include "media_player_proto.h"
#include <string.h>
#include <stdio.h>

/**
 * Decode MediaPlayerCommandRequest (message ID 52)
 *
 * Fields:
 * 1: key (fixed32)
 * 2: has_command (bool)
 * 3: command (MediaPlayerCommand enum/uint32)
 * 4: has_volume (bool)
 * 5: volume (float)
 * 6: has_media_url (bool)
 * 7: media_url (string)
 * 8: has_announcement (bool)
 * 9: announcement (bool)
 */
bool media_player_decode_command_request(const uint8_t *buf, size_t size,
                                           media_player_command_request_t *msg) {
    pb_buffer_t pb;
    pb_buffer_init_read(&pb, buf, size);

    // Initialize with defaults
    memset(msg, 0, sizeof(*msg));

    while (pb.pos < pb.size && !pb.error) {
        uint64_t tag;
        if (!pb_decode_varint(&pb, &tag)) {
            break;
        }

        uint32_t field_num = tag >> 3;
        uint8_t wire_type = tag & 0x07;

        switch (field_num) {
            case 1: // key (fixed32)
                if (wire_type == PB_WIRE_TYPE_32BIT) {
                    if (pb.pos + 4 <= pb.size) {
                        msg->key = *(uint32_t*)(pb.data + pb.pos);
                        pb.pos += 4;
                    }
                }
                break;

            case 2: // has_command
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->has_command = (val != 0);
                    }
                }
                break;

            case 3: // command
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->command = (uint32_t)val;
                    }
                }
                break;

            case 4: // has_volume
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->has_volume = (val != 0);
                    }
                }
                break;

            case 5: // volume (float)
                if (wire_type == PB_WIRE_TYPE_32BIT) {
                    if (pb.pos + 4 <= pb.size) {
                        msg->volume = *(float*)(pb.data + pb.pos);
                        pb.pos += 4;
                    }
                }
                break;

            case 6: // has_media_url
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->has_media_url = (val != 0);
                    }
                }
                break;

            case 7: // media_url (string)
                if (wire_type == PB_WIRE_TYPE_LENGTH) {
                    if (!pb_decode_string(&pb, msg->media_url, sizeof(msg->media_url))) {
                        return false;
                    }
                }
                break;

            case 8: // has_announcement
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->has_announcement = (val != 0);
                    }
                }
                break;

            case 9: // announcement
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->announcement = (val != 0);
                    }
                }
                break;

            default:
                // Skip unknown fields
                if (!pb_skip_field(&pb, wire_type)) {
                    return false;
                }
                break;
        }
    }

    return !pb.error;
}

/**
 * Encode MediaPlayerStateResponse (message ID 51)
 *
 * Fields:
 * 1: key (fixed32)
 * 2: state (MediaPlayerState enum/uint32)
 * 3: volume (float)
 * 4: muted (bool)
 */
size_t media_player_encode_state_response(uint8_t *buf, size_t size,
                                            const media_player_state_response_t *msg) {
    pb_buffer_t pb;
    pb_buffer_init_write(&pb, buf, size);

    // Field 1: key (fixed32)
    uint8_t tag1 = PB_FIELD_TAG(1, PB_WIRE_TYPE_32BIT);
    if (pb.pos + 1 + 4 <= pb.size) {
        pb.data[pb.pos++] = tag1;
        *(uint32_t*)(pb.data + pb.pos) = msg->key;
        pb.pos += 4;
    } else {
        pb.error = true;
    }

    // Field 2: state (uint32 varint)
    if (!pb_encode_uint32(&pb, 2, msg->state)) {
        return 0;
    }

    // Field 3: volume (float)
    uint8_t tag3 = PB_FIELD_TAG(3, PB_WIRE_TYPE_32BIT);
    if (pb.pos + 1 + 4 <= pb.size) {
        pb.data[pb.pos++] = tag3;
        *(float*)(pb.data + pb.pos) = msg->volume;
        pb.pos += 4;
    } else {
        pb.error = true;
    }

    // Field 4: muted (bool)
    if (!pb_encode_bool(&pb, 4, msg->muted)) {
        return 0;
    }

    return pb.error ? 0 : pb.pos;
}

/**
 * Encode ListEntitiesMediaPlayerResponse
 *
 * This is a simplified version - we'll just send the essential fields
 */
size_t media_player_encode_list_entities_response(uint8_t *buf, size_t size,
                                                    const list_entities_media_player_response_t *msg) {
    pb_buffer_t pb;
    pb_buffer_init_write(&pb, buf, size);

    // Field 1: object_id (string)
    if (msg->object_id[0]) {
        if (!pb_encode_string(&pb, 1, msg->object_id)) {
            return 0;
        }
    }

    // Field 2: key (fixed32)
    uint8_t tag2 = PB_FIELD_TAG(2, PB_WIRE_TYPE_32BIT);
    if (pb.pos + 1 + 4 <= pb.size) {
        pb.data[pb.pos++] = tag2;
        *(uint32_t*)(pb.data + pb.pos) = msg->key;
        pb.pos += 4;
    } else {
        pb.error = true;
        return 0;
    }

    // Field 3: name (string)
    if (!pb_encode_string(&pb, 3, msg->name)) {
        return 0;
    }

    // Field 5: icon (string) - optional
    if (msg->icon[0]) {
        if (!pb_encode_string(&pb, 5, msg->icon)) {
            return 0;
        }
    }

    // Field 6: disabled_by_default (bool)
    if (msg->disabled_by_default) {
        if (!pb_encode_bool(&pb, 6, msg->disabled_by_default)) {
            return 0;
        }
    }

    // Field 7: entity_category (uint32)
    if (msg->entity_category) {
        if (!pb_encode_uint32(&pb, 7, msg->entity_category)) {
            return 0;
        }
    }

    // Field 8: supports_pause (bool)
    if (!pb_encode_bool(&pb, 8, msg->supports_pause)) {
        return 0;
    }

    // Field 9: supported_formats (repeated message) - simplified
    // For now, we'll encode each format as a submessage
    for (size_t i = 0; i < msg->formats_count; i++) {
        const media_player_supported_format_t *fmt = &msg->formats[i];

        // Start submessage - we need to encode it to a temp buffer first
        uint8_t format_buf[128];
        pb_buffer_t fmt_pb;
        pb_buffer_init_write(&fmt_pb, format_buf, sizeof(format_buf));

        // Field 1: format (string)
        if (!pb_encode_string(&fmt_pb, 1, fmt->format)) {
            return 0;
        }
        // Field 2: sample_rate (uint32)
        if (!pb_encode_uint32(&fmt_pb, 2, fmt->sample_rate)) {
            return 0;
        }
        // Field 3: num_channels (uint32)
        if (!pb_encode_uint32(&fmt_pb, 3, fmt->num_channels)) {
            return 0;
        }
        // Field 4: purpose (uint32)
        if (fmt->purpose) {
            if (!pb_encode_uint32(&fmt_pb, 4, fmt->purpose)) {
                return 0;
            }
        }
        // Field 5: sample_bytes (uint32)
        if (!pb_encode_uint32(&fmt_pb, 5, fmt->sample_bytes)) {
            return 0;
        }

        // Now encode this as field 9 (repeated)
        if (!pb_encode_bytes(&pb, 9, format_buf, fmt_pb.pos)) {
            return 0;
        }
    }

    // Field 11: feature_flags (uint32)
    if (msg->feature_flags) {
        if (!pb_encode_uint32(&pb, 11, msg->feature_flags)) {
            return 0;
        }
    }

    return pb.error ? 0 : pb.pos;
}
