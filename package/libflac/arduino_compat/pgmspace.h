#ifndef PGMSPACE_H
#define PGMSPACE_H

#include <stdint.h>
#include <string.h>

#ifndef PROGMEM
#define PROGMEM
#endif

#ifndef PGM_P
#define PGM_P const char *
#endif

#ifndef pgm_read_byte
static inline uint8_t pgm_read_byte(const void *addr)
{
    return *(const uint8_t *)addr;
}
#endif

#ifndef pgm_read_word
static inline uint16_t pgm_read_word(const void *addr)
{
    uint16_t value;
    memcpy(&value, addr, sizeof(value));
    return value;
}
#endif

#endif /* PGMSPACE_H */
