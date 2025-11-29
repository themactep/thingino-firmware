/**
 * @file switch_proto.h
 * @brief Protobuf encoding/decoding for ESPHome Switch messages
 *
 * These functions extend esphome_proto.h with MediaPlayer-specific messages.
 */

#ifndef SWITCH_PROTO_H
#define SWITCH_PROTO_H

#include "esphome_proto.h"

/**
 * Switch Command Request structure (message ID 33)
 * From api.proto SwitchCommandRequest
 */
typedef struct {
    uint32_t key;               // Field 1: Entity key
    bool state;                 // Field 2: Command present flag
} switch_command_request_t;

/**
 * Switch State Response structure (message ID 26)
 * From api.proto SwitchStateResponse
 */
typedef struct {
    uint32_t key;               // Field 1: Entity key
    bool state;                 // Field 2: Statr
} switch_state_response_t;


/**
 * List Entities Switch Response structure (message ID 17 in full API)
 * From api.proto ListEntitiesSwitchResponse
 */
typedef struct {
    char object_id[64];         // Field 1: Object ID
    uint32_t key;               // Field 2: Entity key
    char name[128];             // Field 3: Display name
    char icon[64];              // Field 5: Icon
    bool assumed_state;         // Field 6: Assumed state
    bool disabled_by_default;   // Field 7: Disabled by default
    uint32_t entity_category;   // Field 8: Entity category
    char device_class[64];      // Field 9: Device class
} list_entities_switch_response_t;

/**
 * Decode SwitchCommandRequest from protobuf
 *
 * @param buf Protobuf encoded data
 * @param size Size of data
 * @param msg Output structure
 * @return true on success, false on error
 */
bool switch_decode_command_request(const uint8_t *buf, size_t size,
                                    switch_command_request_t *msg);

/**
 * Encode SwitchStateResponse to protobuf
 *
 * @param buf Output buffer
 * @param size Buffer size
 * @param msg State to encode
 * @return Number of bytes written, or 0 on error
 */
size_t switch_encode_state_response(uint8_t *buf, size_t size,
                                    const switch_state_response_t *msg);

/**
 * Encode ListEntitiesMediaPlayerResponse to protobuf
 *
 * @param buf Output buffer
 * @param size Buffer size
 * @param msg Entity info to encode
 * @return Number of bytes written, or 0 on error
 */
size_t switch_encode_list_entities_response(uint8_t *buf, size_t size,
                                            const list_entities_switch_response_t *msg);

#endif /* SWITCH_PROTO_H */
