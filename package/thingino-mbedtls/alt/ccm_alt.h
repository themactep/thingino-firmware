/* SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later */
/*
 * mbedTLS CCM ALT — Ingenic JZ hardware acceleration.
 *
 * Replaces mbedtls_ccm_context when MBEDTLS_CCM_ALT is defined.
 * The hardware-accelerated path lives in ccm_alt.c; the context
 * just holds the round-trip state needed by AES-128/192/256-CCM.
 */
#ifndef MBEDTLS_CCM_ALT_H
#define MBEDTLS_CCM_ALT_H

#include <stdint.h>
#include "mbedtls/aes.h"

typedef struct mbedtls_ccm_context {
    /* Software AES context — used for small records where the ioctl
     * round-trip is more expensive than just computing the AES in CPU,
     * and for the single-block Ctr_0 encryption. */
    mbedtls_aes_context aes_sw;

    /* Raw AES key packed as big-endian 32-bit words, the layout the
     * jz-aes driver writes into AES_ASKY. 8 words covers AES-256. */
    uint32_t hw_key[8];
    int      keybits;      /* 128 / 192 / 256 */
    int      have_key;

    /* Pre-allocated scratch buffers, sized for the largest TLS record
     * (RFC 8446 §5.1: plaintext ≤ 2^14 = 16384 bytes) plus AAD padding
     * and block slack. Reusing these across calls saves 3 malloc + 3
     * free per record — a measurable ~5-7% rsd CPU on T20 at 3 Mbps
     * where the record rate is hundreds per second. */
    unsigned char *scratch_mac;   /* CBC-MAC input staging */
    unsigned char *scratch_ctr;   /* counter blocks */
    unsigned char *scratch_ks;    /* keystream output */
} mbedtls_ccm_context;

/* Scratch buffer size: enough for a max-size TLS record (16 KB) plus
 * the CCM formatting overhead (B_0 = 16, AD length = 2 or 6, plus
 * padding up to 16 bytes) plus some slack. Round up to a page-friendly
 * size for allocator efficiency. */
#define MBEDTLS_CCM_ALT_SCRATCH_SIZE (16 * 1024 + 64)

#endif /* MBEDTLS_CCM_ALT_H */
