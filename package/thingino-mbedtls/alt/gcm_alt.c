// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
/*
 * mbedTLS GCM ALT — Ingenic JZ hardware acceleration.
 *
 * GCM splits into two parts:
 *   1. AES-CTR encryption of the plaintext.
 *      This is the bulk: one AES encrypt per 16-byte counter, XOR'd
 *      with the plaintext. Maps cleanly to HW ECB-batch like CCM.
 *   2. GHASH authentication (GF(2^128) polynomial multiply).
 *      No Ingenic HW for this — stays in software. Naive per-bit
 *      shift/XOR, ~1000 cycles per mult. At 23 K mults/sec for a
 *      3 Mbps stream that's ~3% CPU on T20 — acceptable.
 *
 * Matches the threshold-dispatch pattern from ccm_alt.c: records
 * below CCM_ALT_HW_MIN_SIZE (reused — same threshold tuning) run
 * entirely in CPU to avoid ioctl round-trip cost.
 *
 * Scope: one-shot crypt_and_tag / auth_decrypt (what the TLS record
 * layer calls). Streaming API is stubbed; no TLS consumer uses it.
 */

#include "mbedtls/gcm.h"
#include "mbedtls/aes.h"
#include "mbedtls/error.h"
#include "mbedtls/platform_util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

/* /dev/aes ioctl — same ABI as jz-aes.h, duplicated to keep this TU
 * standalone. Must stay in sync with the kernel module. */
#define JZAES_IOC_MAGIC      'A'
#define IOCTL_AES_DO         _IOW(JZAES_IOC_MAGIC, 113, unsigned int)
#define JZ_AES_MODE_ENC_ECB  0
#define AES_FLAG_BSWAP       (1 << 0)

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

/* Share the threshold with ccm_alt — same ioctl cost applies. */
#ifndef GCM_ALT_HW_MIN_SIZE
#ifdef  CCM_ALT_HW_MIN_SIZE
#define GCM_ALT_HW_MIN_SIZE CCM_ALT_HW_MIN_SIZE
#else
#define GCM_ALT_HW_MIN_SIZE 512
#endif
#endif

/* Stats — mirror ccm_alt's format. */
#ifndef GCM_ALT_STATS_EVERY
#define GCM_ALT_STATS_EVERY 500
#endif
static unsigned long gcm_ops_total;
static unsigned long gcm_bytes_total;
static unsigned long gcm_ops_since_report;
static unsigned long gcm_sw_small;

static int gcm_hw_fd = -1;

static int gcm_hw_fd_get(void)
{
    if (gcm_hw_fd >= 0) return gcm_hw_fd;
    if (gcm_hw_fd == -2) return -1;
    gcm_hw_fd = open("/dev/aes", O_RDWR);
    if (gcm_hw_fd < 0) {
        gcm_hw_fd = -2;
        fprintf(stderr, "gcm_alt: /dev/aes not available, falling back to software\n");
        return -1;
    }
    fprintf(stderr, "gcm_alt: using hardware AES engine (/dev/aes fd=%d)\n", gcm_hw_fd);
    return gcm_hw_fd;
}

static void gcm_stats(unsigned int bytes)
{
    gcm_ops_total++;
    gcm_bytes_total += bytes;
#if GCM_ALT_STATS_EVERY > 0
    if (++gcm_ops_since_report >= GCM_ALT_STATS_EVERY) {
        fprintf(stderr,
                "gcm_alt: %lu HW ops, %lu.%02lu MB through engine, "
                "%lu SW small-record bypasses\n",
                gcm_ops_total,
                gcm_bytes_total / (1024UL * 1024UL),
                (gcm_bytes_total % (1024UL * 1024UL)) * 100UL / (1024UL * 1024UL),
                gcm_sw_small);
        gcm_ops_since_report = 0;
    }
#endif
}

/* ── Byte-order + key packing ─────────────────────────────────────── */

static uint32_t load32_be(const unsigned char *b)
{
    return ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16) |
           ((uint32_t)b[2] <<  8) |  (uint32_t)b[3];
}

static int keybits_to_nwords(int keybits, int *out)
{
    switch (keybits) {
    case 128: *out = 4; return 0;
    case 192: *out = 6; return 0;
    case 256: *out = 8; return 0;
    default:  return -1;
    }
}

static void pack_key(const unsigned char *key, int nwords, uint32_t out[8])
{
    int i;
    for (i = 0; i < nwords; i++)
        out[i] = load32_be(key + i * 4);
}

/* ── HW primitives ─────────────────────────────────────────────────── */

static int hw_ecb_bulk(int fd, const uint32_t key[8], int keybits,
                       const unsigned char *in, size_t n_blocks,
                       unsigned char *out)
{
    struct jz_aes_para p;
    size_t len = n_blocks * 16;

    if (n_blocks == 0) return 0;

    memset(&p, 0, sizeof(p));
    memcpy(p.aeskey, key, keybits / 8);
    memset(p.aesiv, 0, sizeof(p.aesiv));
    p.enworkmode = JZ_AES_MODE_ENC_ECB;
    p.src        = (unsigned char *)in;
    p.dst        = out;
    p.datalen    = (unsigned int)len;
    p.keybits    = keybits;
    p.flags      = AES_FLAG_BSWAP;

    if (ioctl(fd, IOCTL_AES_DO, &p) < 0 || p.donelen != len)
        return -1;

    gcm_stats((unsigned int)len);
    return 0;
}

/* ── GHASH: GF(2^128) multiplication (4-bit table) ────────────────── */

/*
 * 4-bit Shoup-style GHASH.
 *
 * Reduction polynomial R = x^128 + x^7 + x^2 + x + 1. The last4[]
 * table holds the reduction of (r · x^{124}) for each 4-bit r that
 * falls off the top when Z is shifted right by 4 bits — it's the
 * XOR contribution back into the top 16 bits of Z.
 *
 * Algorithm and table ported from mbedtls/library/gcm.c — same
 * license (Apache-2.0 OR GPL-2.0-or-later). We rename the table
 * here to avoid symbol collisions in the single-library build.
 */
static const uint16_t gcm_last4[16] = {
    0x0000, 0x1c20, 0x3840, 0x2460, 0x7080, 0x6ca0, 0x48c0, 0x54e0,
    0xe100, 0xfd20, 0xd940, 0xc560, 0x9180, 0x8da0, 0xa9c0, 0xb5e0
};

static uint64_t load64_be(const unsigned char *b)
{
    return ((uint64_t)b[0] << 56) | ((uint64_t)b[1] << 48) |
           ((uint64_t)b[2] << 40) | ((uint64_t)b[3] << 32) |
           ((uint64_t)b[4] << 24) | ((uint64_t)b[5] << 16) |
           ((uint64_t)b[6] <<  8) |  (uint64_t)b[7];
}

static void store64_be(unsigned char *b, uint64_t v)
{
    b[0] = (unsigned char)(v >> 56);
    b[1] = (unsigned char)(v >> 48);
    b[2] = (unsigned char)(v >> 40);
    b[3] = (unsigned char)(v >> 32);
    b[4] = (unsigned char)(v >> 24);
    b[5] = (unsigned char)(v >> 16);
    b[6] = (unsigned char)(v >>  8);
    b[7] = (unsigned char)(v      );
}

/*
 * Precompute HL[i] / HH[i] = i·H in GF(2^128). Called once at setkey.
 * Table layout: i is a bit-reflected 4-bit index. Derive HL/HH[8]=H,
 * then HL/HH[4]=H·x^{-1}, [2]=H·x^{-2}, [1]=H·x^{-3}. Fill 3,5..7,9..15
 * by XOR combinations.
 */
static void gcm_gen_table(mbedtls_gcm_context *ctx)
{
    uint64_t vh = load64_be(ctx->H);
    uint64_t vl = load64_be(ctx->H + 8);
    int i, j;

    ctx->HL[0] = 0;       ctx->HH[0] = 0;
    ctx->HL[8] = vl;      ctx->HH[8] = vh;

    for (i = 4; i > 0; i >>= 1) {
        uint32_t t = (vl & 1) * 0xe1000000U;
        vl = (vh << 63) | (vl >> 1);
        vh = (vh >> 1) ^ ((uint64_t)t << 32);
        ctx->HL[i] = vl;
        ctx->HH[i] = vh;
    }

    for (i = 2; i <= 8; i *= 2) {
        for (j = 1; j < i; j++) {
            ctx->HL[i + j] = ctx->HL[i] ^ ctx->HL[j];
            ctx->HH[i + j] = ctx->HH[i] ^ ctx->HH[j];
        }
    }
    ctx->have_table = 1;
}

/*
 * Compute Y = Y · H in GF(2^128), using the 4-bit tables. The input
 * X is consumed nibble-by-nibble, low-to-high. Between nibbles we
 * shift Z right 4 bits and XOR the fallen bits against gcm_last4[].
 */
static void gcm_mult(const mbedtls_gcm_context *ctx,
                     const unsigned char x[16],
                     unsigned char out[16])
{
    unsigned char lo, hi, rem;
    uint64_t zh, zl;
    int i;

    lo = x[15] & 0x0F;
    zh = ctx->HH[lo];
    zl = ctx->HL[lo];

    for (i = 15; i >= 0; i--) {
        lo = x[i] & 0x0F;
        hi = (x[i] >> 4) & 0x0F;

        if (i != 15) {
            rem = (unsigned char)zl & 0x0F;
            zl = (zh << 60) | (zl >> 4);
            zh = (zh >> 4) ^ ((uint64_t)gcm_last4[rem] << 48);
            zh ^= ctx->HH[lo];
            zl ^= ctx->HL[lo];
        }

        rem = (unsigned char)zl & 0x0F;
        zl = (zh << 60) | (zl >> 4);
        zh = (zh >> 4) ^ ((uint64_t)gcm_last4[rem] << 48);
        zh ^= ctx->HH[hi];
        zl ^= ctx->HL[hi];
    }

    store64_be(out,     zh);
    store64_be(out + 8, zl);
}

/*
 * GHASH: accumulate a zero-padded message into state Y using H.
 * Both Y and H are 16-byte big-endian blocks. Input @len need not
 * be a multiple of 16 — trailing bytes are treated as zero-padded.
 */
static void ghash_update(const mbedtls_gcm_context *ctx,
                         unsigned char Y[16],
                         const unsigned char *data, size_t len)
{
    unsigned char block[16];
    size_t off;
    int j;

    for (off = 0; off + 16 <= len; off += 16) {
        for (j = 0; j < 16; j++) Y[j] ^= data[off + j];
        gcm_mult(ctx, Y, Y);
    }
    if (off < len) {
        size_t tail = len - off;
        memset(block, 0, 16);
        memcpy(block, data + off, tail);
        for (j = 0; j < 16; j++) Y[j] ^= block[j];
        gcm_mult(ctx, Y, Y);
    }
}

/* Append the 64-bit big-endian length field for the final GHASH block. */
static void put_be64(unsigned char b[8], uint64_t v)
{
    b[0] = (unsigned char)(v >> 56);
    b[1] = (unsigned char)(v >> 48);
    b[2] = (unsigned char)(v >> 40);
    b[3] = (unsigned char)(v >> 32);
    b[4] = (unsigned char)(v >> 24);
    b[5] = (unsigned char)(v >> 16);
    b[6] = (unsigned char)(v >>  8);
    b[7] = (unsigned char)(v      );
}

/* ── CTR keystream ─────────────────────────────────────────────────── */

/*
 * Build n_blocks counter blocks, starting from @j0 incremented by 1
 * (GCM starts the CTR stream at J_0 + 1). Only the rightmost 32 bits
 * of the counter are treated as the counter per SP 800-38D §6.2;
 * earlier bytes are fixed.
 */
static void build_ctr_blocks(unsigned char *ctr, const unsigned char J0[16],
                             size_t n_blocks)
{
    size_t i;
    unsigned int c;

    c = ((unsigned int)J0[12] << 24) | ((unsigned int)J0[13] << 16) |
        ((unsigned int)J0[14] <<  8) |  (unsigned int)J0[15];

    for (i = 0; i < n_blocks; i++) {
        unsigned char *b = ctr + i * 16;
        memcpy(b, J0, 12);
        c++;                                    /* inc_32(J_i) */
        b[12] = (unsigned char)(c >> 24);
        b[13] = (unsigned char)(c >> 16);
        b[14] = (unsigned char)(c >>  8);
        b[15] = (unsigned char)(c      );
    }
}

/* Software ECB-bulk for the small-record path — just a loop through
 * mbedtls_aes_crypt_ecb (which aes_alt provides in software). */
static int sw_ecb_bulk(mbedtls_aes_context *aes,
                       const unsigned char *in, size_t n_blocks,
                       unsigned char *out)
{
    size_t i;
    int ret;
    for (i = 0; i < n_blocks; i++) {
        ret = mbedtls_aes_crypt_ecb(aes, MBEDTLS_AES_ENCRYPT,
                                    in + i * 16, out + i * 16);
        if (ret != 0) return ret;
    }
    return 0;
}

/* ── J_0 derivation ────────────────────────────────────────────────── */

/*
 * NIST SP 800-38D §7.1 step 2:
 *   if |IV|=96 bits:  J_0 = IV || 0^31 || 1
 *   else:             J_0 = GHASH_H(IV || 0^(s+64) || [len(IV) in bits]_64)
 *                     where s = pad-to-128 of IV
 */
static void gcm_derive_j0(const mbedtls_gcm_context *ctx,
                          const unsigned char *iv, size_t iv_len,
                          unsigned char J0[16])
{
    if (iv_len == 12) {
        memcpy(J0, iv, 12);
        J0[12] = 0;
        J0[13] = 0;
        J0[14] = 0;
        J0[15] = 1;
    } else {
        unsigned char len_block[16] = {0};
        memset(J0, 0, 16);
        ghash_update(ctx, J0, iv, iv_len);
        put_be64(len_block + 8, (uint64_t)iv_len * 8);
        ghash_update(ctx, J0, len_block, 16);
    }
}

/* ── One-shot encrypt_and_tag / auth_decrypt ───────────────────────── */

static int gcm_crypt_internal(mbedtls_gcm_context *ctx, size_t length,
                              const unsigned char *iv, size_t iv_len,
                              const unsigned char *ad, size_t ad_len,
                              const unsigned char *input, unsigned char *output)
{
    unsigned char J0[16];
    size_t n_ctr;
    int use_hw;
    size_t i;

    (void)ad; (void)ad_len;            /* AAD handled by caller's GHASH */

    if (length == 0) return 0;
    /* Scratch buffers (ctx->scratch_ctr / scratch_ks) are sized by
     * MBEDTLS_GCM_ALT_SCRATCH_SIZE. Each needs n_ctr * 16 bytes of
     * space where n_ctr = ceil(length/16). With scratch of 16 KB + 64,
     * the safe input limit is exactly SCRATCH_SIZE (which aligns to
     * 16 * (SCRATCH_SIZE/16)). TLS 1.3 records can reach 16385 bytes
     * (16384 plaintext + 1-byte content-type), so the old 16 KB cap
     * was off-by-one and rejected valid records. */
    if (length > MBEDTLS_GCM_ALT_SCRATCH_SIZE) return -1;

    gcm_derive_j0(ctx, iv, iv_len, J0);

    use_hw = ((int)length >= GCM_ALT_HW_MIN_SIZE) && gcm_hw_fd_get() >= 0;

    n_ctr = (length + 15) / 16;
    build_ctr_blocks(ctx->scratch_ctr, J0, n_ctr);

    if (use_hw) {
        if (hw_ecb_bulk(gcm_hw_fd, ctx->hw_key, ctx->keybits,
                        ctx->scratch_ctr, n_ctr, ctx->scratch_ks) != 0)
            return -1;
    } else {
        if (sw_ecb_bulk(&ctx->aes_sw, ctx->scratch_ctr, n_ctr,
                        ctx->scratch_ks) != 0)
            return -1;
        if ((int)length < GCM_ALT_HW_MIN_SIZE)
            gcm_sw_small++;
    }

    for (i = 0; i < length; i++)
        output[i] = input[i] ^ ctx->scratch_ks[i];

    return 0;
}

/*
 * Compute the final tag: GHASH(A || 0 pad || C || 0 pad || [len_A]_64 || [len_C]_64),
 * then XOR with AES_K(J_0) (the initial counter block encrypted).
 */
static int gcm_compute_tag(mbedtls_gcm_context *ctx,
                           const unsigned char *iv, size_t iv_len,
                           const unsigned char *ad, size_t ad_len,
                           const unsigned char *ct, size_t ct_len,
                           unsigned char tag_out[16])
{
    unsigned char J0[16], S[16] = {0}, ek[16], len_block[16] = {0};
    int ret, i;

    gcm_derive_j0(ctx, iv, iv_len, J0);

    /* GHASH(A || 0-pad || C || 0-pad) */
    ghash_update(ctx, S, ad, ad_len);
    ghash_update(ctx, S, ct, ct_len);

    /* Append [len(A)]_64 || [len(C)]_64 (in bits) */
    put_be64(len_block,     (uint64_t)ad_len * 8);
    put_be64(len_block + 8, (uint64_t)ct_len * 8);
    ghash_update(ctx, S, len_block, 16);

    /* tag = S XOR AES_K(J_0) */
    ret = mbedtls_aes_crypt_ecb(&ctx->aes_sw, MBEDTLS_AES_ENCRYPT, J0, ek);
    if (ret != 0) return ret;

    for (i = 0; i < 16; i++)
        tag_out[i] = S[i] ^ ek[i];
    return 0;
}

/* ── mbedtls public API ──────────────────────────────────────────── */

void mbedtls_gcm_init(mbedtls_gcm_context *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
    mbedtls_aes_init(&ctx->aes_sw);
}

void mbedtls_gcm_free(mbedtls_gcm_context *ctx)
{
    if (!ctx) return;
    mbedtls_aes_free(&ctx->aes_sw);
    free(ctx->scratch_ctr);
    free(ctx->scratch_ks);
    mbedtls_platform_zeroize(ctx, sizeof(*ctx));
}

int mbedtls_gcm_setkey(mbedtls_gcm_context *ctx,
                       mbedtls_cipher_id_t cipher,
                       const unsigned char *key,
                       unsigned int keybits)
{
    int nwords, ret;
    unsigned char zero[16] = {0};

    if (cipher != MBEDTLS_CIPHER_ID_AES)
        return MBEDTLS_ERR_GCM_BAD_INPUT;
    if (keybits_to_nwords((int)keybits, &nwords) != 0)
        return MBEDTLS_ERR_GCM_BAD_INPUT;

    pack_key(key, nwords, ctx->hw_key);
    ret = mbedtls_aes_setkey_enc(&ctx->aes_sw, key, keybits);
    if (ret != 0) return ret;

    /* H = AES_K(0^128) — GHASH subkey, computed once per key. */
    ret = mbedtls_aes_crypt_ecb(&ctx->aes_sw, MBEDTLS_AES_ENCRYPT, zero, ctx->H);
    if (ret != 0) return ret;

    /* Derive 4-bit GHASH tables (HL/HH). Eliminates the naive per-bit
     * loop at GHASH time. Cost: ~10 us on T20 (once per setkey). */
    gcm_gen_table(ctx);

    /* Pre-allocate per-record scratch. Reused for every encrypt/decrypt
     * in this connection — saves 2 malloc + 2 free per TLS record. */
    if (!ctx->scratch_ctr)
        ctx->scratch_ctr = malloc(MBEDTLS_GCM_ALT_SCRATCH_SIZE);
    if (!ctx->scratch_ks)
        ctx->scratch_ks  = malloc(MBEDTLS_GCM_ALT_SCRATCH_SIZE);
    if (!ctx->scratch_ctr || !ctx->scratch_ks) {
        free(ctx->scratch_ctr); ctx->scratch_ctr = NULL;
        free(ctx->scratch_ks);  ctx->scratch_ks  = NULL;
        return MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED;
    }

    ctx->keybits  = (int)keybits;
    ctx->have_key = 1;
    return 0;
}

int mbedtls_gcm_crypt_and_tag(mbedtls_gcm_context *ctx, int mode,
                              size_t length,
                              const unsigned char *iv, size_t iv_len,
                              const unsigned char *add, size_t add_len,
                              const unsigned char *input, unsigned char *output,
                              size_t tag_len, unsigned char *tag)
{
    unsigned char full_tag[16];
    int ret;

    if (!ctx->have_key) return MBEDTLS_ERR_GCM_BAD_INPUT;
    if (iv_len == 0) return MBEDTLS_ERR_GCM_BAD_INPUT;
    if (tag_len > 16 || tag_len == 0) return MBEDTLS_ERR_GCM_BAD_INPUT;

    if (mode == MBEDTLS_GCM_ENCRYPT) {
        /* Encrypt with CTR, then GHASH the ciphertext. */
        ret = gcm_crypt_internal(ctx, length, iv, iv_len, add, add_len,
                                 input, output);
        if (ret != 0) return MBEDTLS_ERR_GCM_BAD_INPUT;
        ret = gcm_compute_tag(ctx, iv, iv_len, add, add_len,
                              output, length, full_tag);
        if (ret != 0) return MBEDTLS_ERR_GCM_BAD_INPUT;
        memcpy(tag, full_tag, tag_len);
    } else if (mode == MBEDTLS_GCM_DECRYPT) {
        /* Decrypt is identical to encrypt under CTR. GHASH over the
         * RECEIVED ciphertext (input), not the plaintext output. */
        ret = gcm_compute_tag(ctx, iv, iv_len, add, add_len,
                              input, length, full_tag);
        if (ret != 0) return MBEDTLS_ERR_GCM_BAD_INPUT;
        ret = gcm_crypt_internal(ctx, length, iv, iv_len, add, add_len,
                                 input, output);
        if (ret != 0) return MBEDTLS_ERR_GCM_BAD_INPUT;
        /* Caller compares @tag against full_tag; we don't know which
         * half of crypt_and_tag they'll use, so write the tag and let
         * auth_decrypt (the wrapper) do the compare. */
        memcpy(tag, full_tag, tag_len);
    } else {
        return MBEDTLS_ERR_GCM_BAD_INPUT;
    }

    mbedtls_platform_zeroize(full_tag, sizeof(full_tag));
    return 0;
}

int mbedtls_gcm_auth_decrypt(mbedtls_gcm_context *ctx, size_t length,
                             const unsigned char *iv, size_t iv_len,
                             const unsigned char *add, size_t add_len,
                             const unsigned char *tag, size_t tag_len,
                             const unsigned char *input, unsigned char *output)
{
    unsigned char expected[16];
    int ret;
    size_t i;
    unsigned char diff = 0;

    if (!ctx->have_key) return MBEDTLS_ERR_GCM_BAD_INPUT;
    if (tag_len > 16 || tag_len == 0) return MBEDTLS_ERR_GCM_BAD_INPUT;

    /* Compute expected tag over the received ciphertext first. */
    ret = gcm_compute_tag(ctx, iv, iv_len, add, add_len,
                          input, length, expected);
    if (ret != 0) return MBEDTLS_ERR_GCM_BAD_INPUT;

    /* Constant-time compare; only decrypt if tag matches. */
    for (i = 0; i < tag_len; i++)
        diff |= expected[i] ^ tag[i];

    if (diff != 0) {
        mbedtls_platform_zeroize(output, length);
        mbedtls_platform_zeroize(expected, sizeof(expected));
        return MBEDTLS_ERR_GCM_AUTH_FAILED;
    }

    ret = gcm_crypt_internal(ctx, length, iv, iv_len, add, add_len,
                             input, output);
    mbedtls_platform_zeroize(expected, sizeof(expected));
    if (ret != 0) return MBEDTLS_ERR_GCM_BAD_INPUT;
    return 0;
}

/* ── Streaming API — stubbed (TLS record layer uses the one-shot form) ── */

int mbedtls_gcm_starts(mbedtls_gcm_context *ctx, int mode,
                       const unsigned char *iv, size_t iv_len)
{
    (void)ctx; (void)mode; (void)iv; (void)iv_len;
    return MBEDTLS_ERR_GCM_BAD_INPUT;
}

int mbedtls_gcm_update_ad(mbedtls_gcm_context *ctx,
                          const unsigned char *add, size_t add_len)
{
    (void)ctx; (void)add; (void)add_len;
    return MBEDTLS_ERR_GCM_BAD_INPUT;
}

int mbedtls_gcm_update(mbedtls_gcm_context *ctx,
                       const unsigned char *input, size_t input_length,
                       unsigned char *output, size_t output_size,
                       size_t *output_length)
{
    (void)ctx; (void)input; (void)input_length;
    (void)output; (void)output_size; (void)output_length;
    return MBEDTLS_ERR_GCM_BAD_INPUT;
}

int mbedtls_gcm_finish(mbedtls_gcm_context *ctx,
                       unsigned char *output, size_t output_size,
                       size_t *output_length,
                       unsigned char *tag, size_t tag_len)
{
    (void)ctx; (void)output; (void)output_size; (void)output_length;
    (void)tag; (void)tag_len;
    return MBEDTLS_ERR_GCM_BAD_INPUT;
}

/* mbedtls_gcm_self_test is provided by upstream gcm.c — its definition
 * is not inside the MBEDTLS_GCM_ALT guard, so we must not duplicate it
 * here or the link fails with a multiple-definition error. */
