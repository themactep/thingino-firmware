/**
 * @file switch_proto.c
 * @brief Protobuf encoding/decoding implementation for Switch messages
 */

#include "switch_proto.h"
#include <string.h>
#include <stdio.h>

/**
 * Decode SwitchCommandRequest (message ID 33)
 *
 * Fields:
 * 1: key (fixed32)
 * 2: state (bool)
 */
bool switch_decode_command_request(const uint8_t *buf, size_t size,
                                   switch_command_request_t *msg) {
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

            case 2: // state
                if (wire_type == PB_WIRE_TYPE_VARINT) {
                    uint64_t val;
                    if (pb_decode_varint(&pb, &val)) {
                        msg->state = (val != 0);
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
 * Encode SwitchStateResponse (message ID 26)
 *
 * Fields:
 * 1: key (fixed32)
 * 2: state (bool)
 */
size_t switch_encode_state_response(uint8_t *buf, size_t size,
                                    const switch_state_response_t *msg) {
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

    // Field 2: state (bool)
    if (!pb_encode_bool(&pb, 2, msg->state)) {
        return 0;
    }

    return pb.error ? 0 : pb.pos;
}

/**
 * Encode ListEntitiesSwitchResponse
 *
 * This is a simplified version - we'll just send the essential fields
 */
size_t switch_encode_list_entities_response(uint8_t *buf, size_t size,
                                            const list_entities_switch_response_t *msg) {
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

    // Field 6: assumed_state (bool)
    if (msg->assumed_state) {
        if (!pb_encode_bool(&pb, 6, msg->assumed_state)) {
            return 0;
        }
    }

    // Field 7: disabled_by_default (bool)
    if (msg->disabled_by_default) {
        if (!pb_encode_bool(&pb, 7, msg->disabled_by_default)) {
            return 0;
        }
    }

    // Field 8: entity_category (uint32)
    if (msg->entity_category) {
        if (!pb_encode_uint32(&pb, 8, msg->entity_category)) {
            return 0;
        }
    }

    // Field 9: device_class (string)
    if (!pb_encode_string(&pb, 9, msg->device_class)) {
        return 0;
    }

    return pb.error ? 0 : pb.pos;
}
