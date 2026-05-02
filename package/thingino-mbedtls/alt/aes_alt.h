/* SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later */
/*
 * mbedTLS AES ALT — Ingenic JZ hardware acceleration
 *
 * Replaces mbedtls_aes_context when MBEDTLS_AES_ALT is defined.
 * CBC operations use /dev/aes hardware DMA for bulk throughput.
 * ECB/CTR/CFB/OFB use software AES (ioctl overhead > computation for 16B).
 */
#ifndef MBEDTLS_AES_ALT_H
#define MBEDTLS_AES_ALT_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mbedtls_aes_context {
    /* Software round keys (for ECB/CTR/CFB/OFB single-block ops) */
    int nr;                            /* number of rounds */
    uint32_t rk[68];                   /* round keys (expanded) */

    /* Raw key for hardware CBC path */
    uint32_t hw_key[4];                /* big-endian words for AES_ASKY regs */
    int keybits;                       /* 128, 192, or 256 */
    int has_hw;                        /* 1 if key is 128-bit (hw supported) */
} mbedtls_aes_context;

#if defined(MBEDTLS_CIPHER_MODE_XTS)
typedef struct mbedtls_aes_xts_context {
    mbedtls_aes_context MBEDTLS_PRIVATE(crypt);
    mbedtls_aes_context MBEDTLS_PRIVATE(tweak);
} mbedtls_aes_xts_context;
#endif

#ifdef __cplusplus
}
#endif

#endif /* MBEDTLS_AES_ALT_H */
