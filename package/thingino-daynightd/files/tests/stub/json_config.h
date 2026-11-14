/* Minimal json_config.h stub for HOST-COMPILED parser tests only.
 * Mirrors the subset of the thingino jct json_config API used by
 * daynightd.c so the real daemon source can be included by the test
 * harness without the jct library.  Never shipped or installed. */
#ifndef JSON_CONFIG_STUB_H
#define JSON_CONFIG_STUB_H

#include <stdbool.h>

typedef enum {
    JSON_NULL,
    JSON_BOOL,
    JSON_NUMBER,
    JSON_STRING,
    JSON_ARRAY,
    JSON_OBJECT
} json_type_t;

typedef struct JsonValue {
    json_type_t type;
    union {
        bool boolean;
        struct { long integer; double real; } number;
        char *string;
    } value;
} JsonValue;

static inline JsonValue *load_config(const char *path) { (void)path; return NULL; }
static inline void free_json_value(JsonValue *v) { (void)v; }
static inline JsonValue *get_nested_item(JsonValue *root, const char *path)
{ (void)root; (void)path; return NULL; }

#endif /* JSON_CONFIG_STUB_H */
