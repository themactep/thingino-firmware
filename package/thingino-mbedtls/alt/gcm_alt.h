/* SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later */
/*
 * mbedTLS GCM ALT — Ingenic JZ hardware acceleration.
 *
 * Replaces mbedtls_gcm_context when MBEDTLS_GCM_ALT is defined.
 * GCM = AES-CTR (bulk encrypt) + GHASH (authenticate).
 * CTR goes through /dev/aes for large records; GHASH stays software
 * (the Ingenic engine has no GF(2^128) multiplier).
 */
#ifndef MBEDTLS_GCM_ALT_H
#define MBEDTLS_GCM_ALT_H

#include <stdint.h>
#include "mbedtls/aes.h"

typedef struct mbedtls_gcm_context {
    /* Software AES — drives the small-record path and every single-
     * block op (J_0 encryption for the tag, plus H = AES_K(0)). */
    mbedtls_aes_context aes_sw;

    /* Big-endian packed key for the HW path. 8 words covers AES-256. */
    uint32_t hw_key[8];
    int      keybits;
    int      have_key;

    /* GHASH subkey H = AES_K(0^128), computed once at setkey. */
    unsigned char H[16];

    /* 4-bit GHASH tables — computed once at setkey. HL/HH split as
     * 2 × 64-bit per entry for efficient shift+XOR on 64-bit ops.
     * Speeds GHASH ~8× over naive per-bit at a cost of 256 bytes
     * per context. Algorithm from mbedtls/library/gcm.c (same
     * license: Apache-2.0 / GPL-2.0+). */
    uint64_t HL[16];
    uint64_t HH[16];
    int have_table;

    /* Pre-allocated scratch buffers for the counter stream and
     * keystream — sized for the largest TLS record (16 KB). Reusing
     * them across calls eliminates the 2 malloc + 2 free per record
     * that we otherwise pay, which is ~5% rsd CPU at 3 Mbps on T20. */
    unsigned char *scratch_ctr;
    unsigned char *scratch_ks;
} mbedtls_gcm_context;

#define MBEDTLS_GCM_ALT_SCRATCH_SIZE (16 * 1024 + 64)

#endif /* MBEDTLS_GCM_ALT_H */
