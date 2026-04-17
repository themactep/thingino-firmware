// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
/*
 * mbedTLS AES ALT — Ingenic JZ hardware acceleration
 *
 * Software AES for ECB/CTR/CFB/OFB single-block operations.
 * Hardware /dev/aes for AES-128-CBC bulk operations (the TLS hot path).
 *
 * The software path uses a compact S-box implementation (no T-tables)
 * to keep code size small on embedded targets. Single-block ops are
 * infrequent (SRTP key derivation, CTR nonce init) so speed doesn't matter.
 */

#include "mbedtls/aes.h"
#include "mbedtls/platform_util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

/* ioctl definitions — must match jz-aes driver */
#define JZAES_IOC_MAGIC      'A'
#define IOCTL_AES_INIT        _IOW(JZAES_IOC_MAGIC, 112, unsigned int)
#define IOCTL_AES_PROCESSING  _IOW(JZAES_IOC_MAGIC, 111, unsigned int)
#define IOCTL_AES_DO          _IOW(JZAES_IOC_MAGIC, 113, unsigned int)

#define JZ_AES_MODE_ENC_ECB  0
#define JZ_AES_MODE_DEC_ECB  1
#define JZ_AES_MODE_ENC_CBC  2
#define JZ_AES_MODE_DEC_CBC  3

struct jz_aes_para {
    unsigned int status;
    unsigned int enworkmode;
    unsigned int aeskey[8];
    unsigned int aesiv[4];
    unsigned char *src;
    unsigned char *dst;
    unsigned int datalen;
    unsigned int donelen;
    int keybits;
    unsigned int flags;
};

/* ====================================================================
 * Software AES — compact S-box implementation (AES-128/192/256)
 * ==================================================================== */

static const uint8_t sbox[256] = {
    0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
    0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
    0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
    0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
    0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
    0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
    0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
    0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
    0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
    0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
    0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
    0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
    0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
    0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
    0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
    0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16,
};

static const uint8_t rsbox[256] = {
    0x52,0x09,0x6a,0xd5,0x30,0x36,0xa5,0x38,0xbf,0x40,0xa3,0x9e,0x81,0xf3,0xd7,0xfb,
    0x7c,0xe3,0x39,0x82,0x9b,0x2f,0xff,0x87,0x34,0x8e,0x43,0x44,0xc4,0xde,0xe9,0xcb,
    0x54,0x7b,0x94,0x32,0xa6,0xc2,0x23,0x3d,0xee,0x4c,0x95,0x0b,0x42,0xfa,0xc3,0x4e,
    0x08,0x2e,0xa1,0x66,0x28,0xd9,0x24,0xb2,0x76,0x5b,0xa2,0x49,0x6d,0x8b,0xd1,0x25,
    0x72,0xf8,0xf6,0x64,0x86,0x68,0x98,0x16,0xd4,0xa4,0x5c,0xcc,0x5d,0x65,0xb6,0x92,
    0x6c,0x70,0x48,0x50,0xfd,0xed,0xb9,0xda,0x5e,0x15,0x46,0x57,0xa7,0x8d,0x9d,0x84,
    0x90,0xd8,0xab,0x00,0x8c,0xbc,0xd3,0x0a,0xf7,0xe4,0x58,0x05,0xb8,0xb3,0x45,0x06,
    0xd0,0x2c,0x1e,0x8f,0xca,0x3f,0x0f,0x02,0xc1,0xaf,0xbd,0x03,0x01,0x13,0x8a,0x6b,
    0x3a,0x91,0x11,0x41,0x4f,0x67,0xdc,0xea,0x97,0xf2,0xcf,0xce,0xf0,0xb4,0xe6,0x73,
    0x96,0xac,0x74,0x22,0xe7,0xad,0x35,0x85,0xe2,0xf9,0x37,0xe8,0x1c,0x75,0xdf,0x6e,
    0x47,0xf1,0x1a,0x71,0x1d,0x29,0xc5,0x89,0x6f,0xb7,0x62,0x0e,0xaa,0x18,0xbe,0x1b,
    0xfc,0x56,0x3e,0x4b,0xc6,0xd2,0x79,0x20,0x9a,0xdb,0xc0,0xfe,0x78,0xcd,0x5a,0xf4,
    0x1f,0xdd,0xa8,0x33,0x88,0x07,0xc7,0x31,0xb1,0x12,0x10,0x59,0x27,0x80,0xec,0x5f,
    0x60,0x51,0x7f,0xa9,0x19,0xb5,0x4a,0x0d,0x2d,0xe5,0x7a,0x9f,0x93,0xc9,0x9c,0xef,
    0xa0,0xe0,0x3b,0x4d,0xae,0x2a,0xf5,0xb0,0xc8,0xeb,0xbb,0x3c,0x83,0x53,0x99,0x61,
    0x17,0x2b,0x04,0x7e,0xba,0x77,0xd6,0x26,0xe1,0x69,0x14,0x63,0x55,0x21,0x0c,0x7d,
};

static const uint8_t rcon[11] = {
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
};

static inline uint32_t load32_be(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
}

static inline void store32_be(uint8_t *p, uint32_t x)
{
    p[0] = (uint8_t)(x >> 24);
    p[1] = (uint8_t)(x >> 16);
    p[2] = (uint8_t)(x >> 8);
    p[3] = (uint8_t)(x);
}

static inline uint32_t sub_word(uint32_t w)
{
    return ((uint32_t)sbox[(w >> 24) & 0xff] << 24) |
           ((uint32_t)sbox[(w >> 16) & 0xff] << 16) |
           ((uint32_t)sbox[(w >>  8) & 0xff] <<  8) |
           ((uint32_t)sbox[(w)       & 0xff]);
}

static inline uint32_t rot_word(uint32_t w)
{
    return (w << 8) | (w >> 24);
}

/* GF(2^8) multiply by 2 */
static inline uint8_t xtime(uint8_t x)
{
    return (uint8_t)((x << 1) ^ (((x >> 7) & 1) * 0x1b));
}

static inline uint8_t gmul(uint8_t a, uint8_t b)
{
    uint8_t p = 0;
    for (int i = 0; i < 8; i++) {
        if (b & 1) p ^= a;
        uint8_t hi = a & 0x80;
        a <<= 1;
        if (hi) a ^= 0x1b;
        b >>= 1;
    }
    return p;
}

/*
 * Key expansion — works for 128/192/256
 * Stores round keys as big-endian words in rk[]
 */
static void sw_key_expand(uint32_t *rk, const uint8_t *key, int keybits)
{
    int nk = keybits / 32;   /* 4, 6, or 8 */
    int nr = nk + 6;         /* 10, 12, or 14 */
    int total = 4 * (nr + 1);
    int i;

    for (i = 0; i < nk; i++)
        rk[i] = load32_be(key + 4 * i);

    for (i = nk; i < total; i++) {
        uint32_t tmp = rk[i - 1];
        if (i % nk == 0)
            tmp = sub_word(rot_word(tmp)) ^ ((uint32_t)rcon[i / nk] << 24);
        else if (nk > 6 && i % nk == 4)
            tmp = sub_word(tmp);
        rk[i] = rk[i - nk] ^ tmp;
    }
}

/* Software AES block encrypt (16 bytes) */
static void sw_encrypt_block(const uint32_t *rk, int nr,
                             const uint8_t in[16], uint8_t out[16])
{
    uint8_t state[16];
    int i, j, round;

    memcpy(state, in, 16);

    /* AddRoundKey (initial) */
    for (i = 0; i < 4; i++) {
        uint32_t k = rk[i];
        state[4*i+0] ^= (uint8_t)(k >> 24);
        state[4*i+1] ^= (uint8_t)(k >> 16);
        state[4*i+2] ^= (uint8_t)(k >> 8);
        state[4*i+3] ^= (uint8_t)(k);
    }

    for (round = 1; round <= nr; round++) {
        uint8_t tmp[16];

        /* SubBytes */
        for (i = 0; i < 16; i++)
            tmp[i] = sbox[state[i]];

        /* ShiftRows */
        state[0]  = tmp[0];  state[1]  = tmp[5];  state[2]  = tmp[10]; state[3]  = tmp[15];
        state[4]  = tmp[4];  state[5]  = tmp[9];  state[6]  = tmp[14]; state[7]  = tmp[3];
        state[8]  = tmp[8];  state[9]  = tmp[13]; state[10] = tmp[2];  state[11] = tmp[7];
        state[12] = tmp[12]; state[13] = tmp[1];  state[14] = tmp[6];  state[15] = tmp[11];

        /* MixColumns (skip on final round) */
        if (round < nr) {
            for (j = 0; j < 4; j++) {
                uint8_t *col = &state[4*j];
                uint8_t a = col[0], b = col[1], c = col[2], d = col[3];
                col[0] = xtime(a) ^ xtime(b) ^ b ^ c ^ d;
                col[1] = a ^ xtime(b) ^ xtime(c) ^ c ^ d;
                col[2] = a ^ b ^ xtime(c) ^ xtime(d) ^ d;
                col[3] = xtime(a) ^ a ^ b ^ c ^ xtime(d);
            }
        }

        /* AddRoundKey */
        for (i = 0; i < 4; i++) {
            uint32_t k = rk[round * 4 + i];
            state[4*i+0] ^= (uint8_t)(k >> 24);
            state[4*i+1] ^= (uint8_t)(k >> 16);
            state[4*i+2] ^= (uint8_t)(k >> 8);
            state[4*i+3] ^= (uint8_t)(k);
        }
    }

    memcpy(out, state, 16);
}

/* Software AES block decrypt (16 bytes) */
static void sw_decrypt_block(const uint32_t *rk, int nr,
                             const uint8_t in[16], uint8_t out[16])
{
    uint8_t state[16];
    int i, j, round;

    memcpy(state, in, 16);

    /* AddRoundKey (final round key) */
    for (i = 0; i < 4; i++) {
        uint32_t k = rk[nr * 4 + i];
        state[4*i+0] ^= (uint8_t)(k >> 24);
        state[4*i+1] ^= (uint8_t)(k >> 16);
        state[4*i+2] ^= (uint8_t)(k >> 8);
        state[4*i+3] ^= (uint8_t)(k);
    }

    for (round = nr - 1; round >= 0; round--) {
        uint8_t tmp[16];

        /* InvShiftRows */
        tmp[0]  = state[0];  tmp[5]  = state[1];  tmp[10] = state[2];  tmp[15] = state[3];
        tmp[4]  = state[4];  tmp[9]  = state[5];  tmp[14] = state[6];  tmp[3]  = state[7];
        tmp[8]  = state[8];  tmp[13] = state[9];  tmp[2]  = state[10]; tmp[7]  = state[11];
        tmp[12] = state[12]; tmp[1]  = state[13]; tmp[6]  = state[14]; tmp[11] = state[15];

        /* InvSubBytes */
        for (i = 0; i < 16; i++)
            state[i] = rsbox[tmp[i]];

        /* AddRoundKey */
        for (i = 0; i < 4; i++) {
            uint32_t k = rk[round * 4 + i];
            state[4*i+0] ^= (uint8_t)(k >> 24);
            state[4*i+1] ^= (uint8_t)(k >> 16);
            state[4*i+2] ^= (uint8_t)(k >> 8);
            state[4*i+3] ^= (uint8_t)(k);
        }

        /* InvMixColumns (skip on round 0) */
        if (round > 0) {
            for (j = 0; j < 4; j++) {
                uint8_t *col = &state[4*j];
                uint8_t a = col[0], b = col[1], c = col[2], d = col[3];
                col[0] = gmul(a,14) ^ gmul(b,11) ^ gmul(c,13) ^ gmul(d,9);
                col[1] = gmul(a,9)  ^ gmul(b,14) ^ gmul(c,11) ^ gmul(d,13);
                col[2] = gmul(a,13) ^ gmul(b,9)  ^ gmul(c,14) ^ gmul(d,11);
                col[3] = gmul(a,11) ^ gmul(b,13) ^ gmul(c,9)  ^ gmul(d,14);
            }
        }
    }

    memcpy(out, state, 16);
}

/* ====================================================================
 * Hardware AES CBC via /dev/aes
 * ==================================================================== */

/* aes_para.flags — must match jz-aes driver */
#define AES_FLAG_BSWAP  (1 << 0)

/*
 * Hardware AES-128-CBC via /dev/aes
 * Returns 0 on success, -1 on failure (caller falls back to software).
 *
 * The JZ AES hardware on MIPSEL expects:
 *   - Key: written as big-endian words to AES_ASKY registers (handled by driver)
 *   - IV:  written as big-endian words to AES_ASIV registers (handled by driver)
 *   - DMA data: each 32-bit word byte-swapped vs standard byte order
 */
/*
 * Cached /dev/aes fd — opened once on first use, kept for process lifetime.
 * -1 = not tried, -2 = tried and failed (no module), >= 0 = valid fd.
 */
static int hw_fd = -1;

/*
 * Observability: count HW CBC ops and total bytes, emit a stderr line every
 * AES_ALT_STATS_EVERY ops. Keeps output low (~once every few seconds of
 * active streaming) but confirms the HW is actually being hit. Disable by
 * setting AES_ALT_STATS_EVERY to 0 at build time.
 */
#ifndef AES_ALT_STATS_EVERY
#define AES_ALT_STATS_EVERY 1000
#endif
static unsigned long hw_ops_total;
static unsigned long hw_bytes_total;
static unsigned long hw_ops_since_report;

static int hw_get_fd(void)
{
    if (hw_fd >= 0)
        return hw_fd;
    if (hw_fd == -2)
        return -1; /* already failed, don't retry */

    hw_fd = open("/dev/aes", O_RDWR);
    if (hw_fd < 0) {
        hw_fd = -2;
        fprintf(stderr, "aes_alt: /dev/aes not available, using software AES\n");
        return -1;
    }
    fprintf(stderr, "aes_alt: using hardware AES engine (/dev/aes fd=%d)\n", hw_fd);
    return hw_fd;
}

static void hw_count(unsigned int bytes)
{
    hw_ops_total++;
    hw_bytes_total += bytes;
#if AES_ALT_STATS_EVERY > 0
    if (++hw_ops_since_report >= AES_ALT_STATS_EVERY) {
        fprintf(stderr,
                "aes_alt: %lu HW CBC ops, %lu.%02lu MB through engine\n",
                hw_ops_total,
                hw_bytes_total / (1024UL * 1024UL),
                (hw_bytes_total % (1024UL * 1024UL)) * 100UL / (1024UL * 1024UL));
        hw_ops_since_report = 0;
    }
#endif
}

static int hw_cbc(const uint32_t hw_key[4],
                  unsigned char iv[16],
                  int mode, /* MBEDTLS_AES_ENCRYPT or MBEDTLS_AES_DECRYPT */
                  size_t length,
                  const unsigned char *input,
                  unsigned char *output)
{
    int fd, ret = -1;
    struct jz_aes_para p;

    fd = hw_get_fd();
    if (fd < 0)
        return -1;

    memset(&p, 0, sizeof(p));
    memcpy(p.aeskey, hw_key, 16);

    /* IV as big-endian words */
    p.aesiv[0] = load32_be(iv);
    p.aesiv[1] = load32_be(iv + 4);
    p.aesiv[2] = load32_be(iv + 8);
    p.aesiv[3] = load32_be(iv + 12);

    p.enworkmode = (mode == MBEDTLS_AES_ENCRYPT)
                   ? JZ_AES_MODE_ENC_CBC : JZ_AES_MODE_DEC_CBC;
    p.src = (unsigned char *)input;
    p.dst = output;
    p.datalen = (unsigned int)length;
    p.flags = AES_FLAG_BSWAP;  /* driver does byte-swap during copy */

    /* single ioctl: init + processing, with key caching */
    if (ioctl(fd, IOCTL_AES_DO, &p) < 0)
        return -1;
    if (p.donelen != length)
        return -1;

    hw_count((unsigned int)length);

    /* Update IV: last ciphertext block (CBC convention) */
    if (mode == MBEDTLS_AES_ENCRYPT)
        memcpy(iv, output + length - 16, 16);
    else
        memcpy(iv, input + length - 16, 16);

    ret = 0;
    return ret;
}

/* ====================================================================
 * mbedTLS AES ALT API
 * ==================================================================== */

void mbedtls_aes_init(mbedtls_aes_context *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
}

void mbedtls_aes_free(mbedtls_aes_context *ctx)
{
    if (ctx == NULL)
        return;
    mbedtls_platform_zeroize(ctx, sizeof(*ctx));
}

int mbedtls_aes_setkey_enc(mbedtls_aes_context *ctx,
                           const unsigned char *key, unsigned int keybits)
{
    if (keybits != 128 && keybits != 192 && keybits != 256)
        return MBEDTLS_ERR_AES_INVALID_KEY_LENGTH;

    ctx->keybits = (int)keybits;
    ctx->nr = (int)(keybits / 32) + 6;  /* 10, 12, or 14 */

    /* Software round keys */
    sw_key_expand(ctx->rk, key, (int)keybits);

    /* Hardware path: only AES-128 */
    if (keybits == 128) {
        ctx->hw_key[0] = load32_be(key);
        ctx->hw_key[1] = load32_be(key + 4);
        ctx->hw_key[2] = load32_be(key + 8);
        ctx->hw_key[3] = load32_be(key + 12);
        ctx->has_hw = 1;
    } else {
        ctx->has_hw = 0;
    }

    return 0;
}

int mbedtls_aes_setkey_dec(mbedtls_aes_context *ctx,
                           const unsigned char *key, unsigned int keybits)
{
    /* Same key expansion — direction is determined at crypt time */
    return mbedtls_aes_setkey_enc(ctx, key, keybits);
}

int mbedtls_internal_aes_encrypt(mbedtls_aes_context *ctx,
                                 const unsigned char input[16],
                                 unsigned char output[16])
{
    sw_encrypt_block(ctx->rk, ctx->nr, input, output);
    return 0;
}

int mbedtls_internal_aes_decrypt(mbedtls_aes_context *ctx,
                                 const unsigned char input[16],
                                 unsigned char output[16])
{
    sw_decrypt_block(ctx->rk, ctx->nr, input, output);
    return 0;
}

int mbedtls_aes_crypt_ecb(mbedtls_aes_context *ctx,
                          int mode,
                          const unsigned char input[16],
                          unsigned char output[16])
{
    /* Always software for single-block ECB — ioctl overhead > AES computation */
    if (mode == MBEDTLS_AES_ENCRYPT)
        sw_encrypt_block(ctx->rk, ctx->nr, input, output);
    else
        sw_decrypt_block(ctx->rk, ctx->nr, input, output);
    return 0;
}

#if defined(MBEDTLS_CIPHER_MODE_CBC)
int mbedtls_aes_crypt_cbc(mbedtls_aes_context *ctx,
                          int mode,
                          size_t length,
                          unsigned char iv[16],
                          const unsigned char *input,
                          unsigned char *output)
{
    if (length % 16)
        return MBEDTLS_ERR_AES_INVALID_INPUT_LENGTH;
    if (length == 0)
        return 0;

    /* Try hardware path for AES-128 CBC */
    if (ctx->has_hw && length >= 32) {
        /* Save IV for decrypt (input may be overwritten if in-place) */
        unsigned char saved_iv[16];
        if (mode == MBEDTLS_AES_DECRYPT)
            memcpy(saved_iv, input + length - 16, 16);

        if (hw_cbc(ctx->hw_key, iv, mode, length, input, output) == 0) {
            if (mode == MBEDTLS_AES_DECRYPT)
                memcpy(iv, saved_iv, 16);
            return 0;
        }
        /* Hardware failed — fall through to software */
    }

    /* Software CBC */
    if (mode == MBEDTLS_AES_ENCRYPT) {
        while (length > 0) {
            for (int i = 0; i < 16; i++)
                output[i] = input[i] ^ iv[i];
            sw_encrypt_block(ctx->rk, ctx->nr, output, output);
            memcpy(iv, output, 16);
            input += 16;
            output += 16;
            length -= 16;
        }
    } else {
        while (length > 0) {
            unsigned char tmp[16];
            memcpy(tmp, input, 16);
            sw_decrypt_block(ctx->rk, ctx->nr, input, output);
            for (int i = 0; i < 16; i++)
                output[i] ^= iv[i];
            memcpy(iv, tmp, 16);
            input += 16;
            output += 16;
            length -= 16;
        }
    }

    return 0;
}
#endif /* MBEDTLS_CIPHER_MODE_CBC */

#if defined(MBEDTLS_CIPHER_MODE_CFB)
int mbedtls_aes_crypt_cfb128(mbedtls_aes_context *ctx,
                             int mode, size_t length, size_t *iv_off,
                             unsigned char iv[16],
                             const unsigned char *input,
                             unsigned char *output)
{
    size_t n = *iv_off;

    if (mode == MBEDTLS_AES_DECRYPT) {
        while (length--) {
            if (n == 0)
                sw_encrypt_block(ctx->rk, ctx->nr, iv, iv);
            unsigned char c = *input++;
            *output++ = c ^ iv[n];
            iv[n] = c;
            n = (n + 1) & 15;
        }
    } else {
        while (length--) {
            if (n == 0)
                sw_encrypt_block(ctx->rk, ctx->nr, iv, iv);
            iv[n] = *output++ = *input++ ^ iv[n];
            n = (n + 1) & 15;
        }
    }
    *iv_off = n;
    return 0;
}

int mbedtls_aes_crypt_cfb8(mbedtls_aes_context *ctx,
                           int mode, size_t length,
                           unsigned char iv[16],
                           const unsigned char *input,
                           unsigned char *output)
{
    unsigned char ov[17];

    while (length--) {
        memcpy(ov, iv, 16);
        sw_encrypt_block(ctx->rk, ctx->nr, iv, iv);
        if (mode == MBEDTLS_AES_DECRYPT)
            ov[16] = *input;
        *output++ = *input++ ^ iv[0];
        if (mode == MBEDTLS_AES_ENCRYPT)
            ov[16] = *(output - 1);
        memcpy(iv, ov + 1, 16);
    }
    return 0;
}
#endif /* MBEDTLS_CIPHER_MODE_CFB */

#if defined(MBEDTLS_CIPHER_MODE_OFB)
int mbedtls_aes_crypt_ofb(mbedtls_aes_context *ctx, size_t length,
                          size_t *iv_off, unsigned char iv[16],
                          const unsigned char *input,
                          unsigned char *output)
{
    size_t n = *iv_off;

    while (length--) {
        if (n == 0)
            sw_encrypt_block(ctx->rk, ctx->nr, iv, iv);
        *output++ = *input++ ^ iv[n];
        n = (n + 1) & 15;
    }
    *iv_off = n;
    return 0;
}
#endif /* MBEDTLS_CIPHER_MODE_OFB */

#if defined(MBEDTLS_CIPHER_MODE_CTR)
int mbedtls_aes_crypt_ctr(mbedtls_aes_context *ctx, size_t length,
                          size_t *nc_off, unsigned char nonce_counter[16],
                          unsigned char stream_block[16],
                          const unsigned char *input,
                          unsigned char *output)
{
    size_t n = *nc_off;
    int i;

    while (length--) {
        if (n == 0) {
            sw_encrypt_block(ctx->rk, ctx->nr, nonce_counter, stream_block);
            /* Increment counter (big-endian, last 4 bytes) */
            for (i = 15; i >= 0; i--) {
                if (++nonce_counter[i] != 0)
                    break;
            }
        }
        *output++ = *input++ ^ stream_block[n];
        n = (n + 1) & 15;
    }
    *nc_off = n;
    return 0;
}
#endif /* MBEDTLS_CIPHER_MODE_CTR */

#if defined(MBEDTLS_CIPHER_MODE_XTS)

/* Access XTS sub-contexts through MBEDTLS_PRIVATE() */
#define XTS_CRYPT(ctx) (&(ctx)->MBEDTLS_PRIVATE(crypt))
#define XTS_TWEAK(ctx) (&(ctx)->MBEDTLS_PRIVATE(tweak))

void mbedtls_aes_xts_init(mbedtls_aes_xts_context *ctx)
{
    mbedtls_aes_init(XTS_CRYPT(ctx));
    mbedtls_aes_init(XTS_TWEAK(ctx));
}

void mbedtls_aes_xts_free(mbedtls_aes_xts_context *ctx)
{
    if (ctx == NULL)
        return;
    mbedtls_aes_free(XTS_CRYPT(ctx));
    mbedtls_aes_free(XTS_TWEAK(ctx));
}

int mbedtls_aes_xts_setkey_enc(mbedtls_aes_xts_context *ctx,
                               const unsigned char *key,
                               unsigned int keybits)
{
    unsigned int half = keybits / 2;
    int ret;

    ret = mbedtls_aes_setkey_enc(XTS_CRYPT(ctx), key, half);
    if (ret)
        return ret;
    return mbedtls_aes_setkey_enc(XTS_TWEAK(ctx), key + half / 8, half);
}

int mbedtls_aes_xts_setkey_dec(mbedtls_aes_xts_context *ctx,
                               const unsigned char *key,
                               unsigned int keybits)
{
    unsigned int half = keybits / 2;
    int ret;

    ret = mbedtls_aes_setkey_dec(XTS_CRYPT(ctx), key, half);
    if (ret)
        return ret;
    return mbedtls_aes_setkey_enc(XTS_TWEAK(ctx), key + half / 8, half);
}

/* GF(2^128) multiply tweak by x */
static void xts_mul_tweak(unsigned char tweak[16])
{
    unsigned char cin = 0, cout;
    size_t j;
    for (j = 0; j < 16; j++) {
        cout = (tweak[j] >> 7) & 1;
        tweak[j] = (unsigned char)((tweak[j] << 1) | cin);
        cin = cout;
    }
    if (cout)
        tweak[0] ^= 0x87;
}

int mbedtls_aes_crypt_xts(mbedtls_aes_xts_context *ctx, int mode,
                          size_t length, const unsigned char data_unit[16],
                          const unsigned char *input, unsigned char *output)
{
    unsigned char tweak[16], next_tweak[16], prev[16], tmp[16];
    size_t blocks, i, j, leftover;

    if (length < 16)
        return MBEDTLS_ERR_AES_INVALID_INPUT_LENGTH;

    /* encrypt tweak */
    mbedtls_aes_crypt_ecb(XTS_TWEAK(ctx), MBEDTLS_AES_ENCRYPT,
                          data_unit, tweak);

    blocks = length / 16;
    leftover = length % 16;
    if (leftover)
        blocks--;

    for (i = 0; i < blocks; i++) {
        for (j = 0; j < 16; j++)
            tmp[j] = input[j] ^ tweak[j];
        mbedtls_aes_crypt_ecb(XTS_CRYPT(ctx), mode, tmp, tmp);
        for (j = 0; j < 16; j++)
            output[j] = tmp[j] ^ tweak[j];

        xts_mul_tweak(tweak);
        input += 16;
        output += 16;
    }

    /* ciphertext stealing for partial final block */
    if (leftover) {
        memcpy(next_tweak, tweak, 16);
        xts_mul_tweak(next_tweak);

        if (mode == MBEDTLS_AES_DECRYPT) {
            for (j = 0; j < 16; j++)
                tmp[j] = input[j] ^ next_tweak[j];
            mbedtls_aes_crypt_ecb(XTS_CRYPT(ctx), mode, tmp, tmp);
            for (j = 0; j < 16; j++)
                tmp[j] ^= next_tweak[j];

            for (j = 0; j < leftover; j++)
                output[16 + j] = tmp[j];
            memcpy(prev, tmp, 16);
            for (j = 0; j < leftover; j++)
                prev[j] = input[16 + j];
            for (j = 0; j < 16; j++)
                tmp[j] = prev[j] ^ tweak[j];
            mbedtls_aes_crypt_ecb(XTS_CRYPT(ctx), mode, tmp, tmp);
            for (j = 0; j < 16; j++)
                output[j] = tmp[j] ^ tweak[j];
        } else {
            for (j = 0; j < 16; j++)
                tmp[j] = input[j] ^ tweak[j];
            mbedtls_aes_crypt_ecb(XTS_CRYPT(ctx), mode, tmp, tmp);
            for (j = 0; j < 16; j++)
                tmp[j] ^= tweak[j];

            for (j = 0; j < leftover; j++)
                output[16 + j] = tmp[j];
            memcpy(prev, tmp, 16);
            for (j = 0; j < leftover; j++)
                prev[j] = input[16 + j];
            for (j = 0; j < 16; j++)
                tmp[j] = prev[j] ^ next_tweak[j];
            mbedtls_aes_crypt_ecb(XTS_CRYPT(ctx), mode, tmp, tmp);
            for (j = 0; j < 16; j++)
                output[j] = tmp[j] ^ next_tweak[j];
        }
    }

    return 0;
}
#endif /* MBEDTLS_CIPHER_MODE_XTS */
