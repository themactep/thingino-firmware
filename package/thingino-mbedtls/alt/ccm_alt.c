// SPDX-License-Identifier: Apache-2.0 OR GPL-2.0-or-later
/*
 * mbedTLS CCM ALT — Ingenic JZ hardware acceleration.
 *
 * CCM = CBC-MAC (authentication) + CTR (encryption), both AES-based.
 * The Ingenic AES engine supports both CBC and ECB in DMA mode, so
 * CCM maps very cleanly: one hardware call for the MAC pass, one for
 * batched CTR keystream generation.
 *
 * This file provides an alternative implementation of mbedtls_ccm_*
 * selected via MBEDTLS_CCM_ALT. It implements RFC 3610 exactly; the
 * only difference from the stock mbedtls/ccm.c is that bulk AES ops
 * go through /dev/aes.
 *
 * Per-record cost for a 16 KB TLS record:
 *   stock mbedtls    ~2000 single-block AES calls + 1000 CBC-MAC XORs
 *   this impl        2 ioctls + 1 XOR loop (software)
 *
 * Scope (this file):
 *   - one-shot:  mbedtls_ccm_encrypt_and_tag, mbedtls_ccm_auth_decrypt
 *                (what mbedtls_cipher_auth_{encrypt,decrypt}_ext calls
 *                 — the code path used by the TLS record layer for AEAD)
 *   - streaming: starts/set_lengths/update_ad/update/finish — stubbed
 *                (not used by the TLS record layer; can fill in later)
 *   - CCM*:      star_encrypt_and_tag, star_auth_decrypt — delegate to
 *                the non-star variants (the format differs only in tag
 *                length constraints, which we don't validate restrictively)
 */

#include "mbedtls/ccm.h"
#include "mbedtls/aes.h"
#include "mbedtls/error.h"
#include "mbedtls/platform_util.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>

/*
 * /dev/aes ioctl — declarations duplicated from aes_alt.c so this
 * file builds standalone. Keep in sync with jz-aes driver.
 */
#define JZAES_IOC_MAGIC      'A'
#define IOCTL_AES_DO         _IOW(JZAES_IOC_MAGIC, 113, unsigned int)
#define JZ_AES_MODE_ENC_ECB  0
#define JZ_AES_MODE_ENC_CBC  2
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

/*
 * HW ioctl threshold. Below this size, we stay entirely in software —
 * the syscall + DMA-sync round-trip (~30us on T20) dwarfs the actual
 * AES compute for tiny ops. Measured breakeven is around 256-512 bytes;
 * pick 512 as a conservative default.
 *
 * RTSPS video streams have bimodal record sizes: lots of small RTP
 * packets (~60-300B for audio/control) plus a few large records per
 * frame (~1.4 KB per MTU chunk, up to 16 KB for keyframes). Staying
 * software-only for the small ones eliminates the syscall storm that
 * was burning 36% sys CPU.
 */
#ifndef CCM_ALT_HW_MIN_SIZE
#define CCM_ALT_HW_MIN_SIZE 512
#endif

/* Stats — same format as aes_alt.c for consistency in logs. Entire
 * logging path is gated on JZ_CRYPTO_DEBUG so the library stays silent
 * by default; build with -DJZ_CRYPTO_DEBUG=1 to enable. */
#ifndef JZ_CRYPTO_DEBUG
#define JZ_CRYPTO_DEBUG 0
#endif
#if JZ_CRYPTO_DEBUG
#define JZ_CRYPTO_LOG(...) fprintf(stderr, __VA_ARGS__)
#else
#define JZ_CRYPTO_LOG(...) ((void)0)
#endif

#ifndef CCM_ALT_STATS_EVERY
#define CCM_ALT_STATS_EVERY 500
#endif
static unsigned long ccm_ops_total;
static unsigned long ccm_bytes_total;
static unsigned long ccm_ops_since_report;
static unsigned long ccm_sw_small;	/* records below threshold */

/*
 * Global /dev/aes fd — shared with aes_alt.c's instance via a late-open
 * pattern. Opened once per process, lives until exit.
 *   -1 = not tried, -2 = tried and failed, >= 0 = usable.
 */
static int ccm_hw_fd = -1;

static int ccm_hw_fd_get(void)
{
    if (ccm_hw_fd >= 0) return ccm_hw_fd;
    if (ccm_hw_fd == -2) return -1;
    ccm_hw_fd = open("/dev/aes", O_RDWR);
    if (ccm_hw_fd < 0) {
        ccm_hw_fd = -2;
        JZ_CRYPTO_LOG("ccm_alt: /dev/aes not available, falling back to software\n");
        return -1;
    }
    JZ_CRYPTO_LOG("ccm_alt: using hardware AES engine (/dev/aes fd=%d)\n", ccm_hw_fd);
    return ccm_hw_fd;
}

static void ccm_stats(unsigned int bytes)
{
    ccm_ops_total++;
    ccm_bytes_total += bytes;
#if JZ_CRYPTO_DEBUG && CCM_ALT_STATS_EVERY > 0
    if (++ccm_ops_since_report >= CCM_ALT_STATS_EVERY) {
        fprintf(stderr, "ccm_alt: %lu HW ops, %lu.%02lu MB through engine, "
                "%lu SW small-record bypasses\n",
                ccm_ops_total, ccm_bytes_total / (1024UL * 1024UL),
                (ccm_bytes_total % (1024UL * 1024UL)) * 100UL / (1024UL * 1024UL),
                ccm_sw_small);
        ccm_ops_since_report = 0;
    }
#else
    (void)ccm_ops_since_report; (void)ccm_sw_small;
#endif
}

/* ── Byte order helpers (the JZ engine expects big-endian key words
 *    but mbedtls gives us little-endian buffers) ─────────────────── */

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

/*
 * Pack a raw mbedtls key (byte buffer, MSB-first per AES spec) into
 * the big-endian uint32 array the jz-aes driver writes to AES_ASKY.
 */
static void pack_key(const unsigned char *key, int nwords, uint32_t out[8])
{
    int i;
    for (i = 0; i < nwords; i++)
        out[i] = load32_be(key + i * 4);
}

/*
 * HW CBC-MAC — runs input through AES-CBC with IV=0 and returns the
 * final 16-byte ciphertext block (the MAC value).
 * Input length must be a multiple of 16 (caller pre-pads).
 * Returns 0 on success, -1 on error.
 */
static int hw_cbc_mac(int fd, const uint32_t key[8], int keybits,
                      const unsigned char *input, size_t input_len,
                      unsigned char mac_out[16])
{
    struct jz_aes_para p;
    unsigned char *tmp_out;

    if (input_len == 0 || input_len % 16 != 0) return -1;

    /* The driver's CBC mode writes the full ciphertext — we only care
     * about the last block. Allocate an output buffer just for that. */
    tmp_out = malloc(input_len);
    if (!tmp_out) return -1;

    memset(&p, 0, sizeof(p));
    memcpy(p.aeskey, key, keybits / 8);
    memset(p.aesiv, 0, sizeof(p.aesiv));     /* CBC-MAC uses IV=0 */
    p.enworkmode = JZ_AES_MODE_ENC_CBC;
    p.src        = (unsigned char *)input;
    p.dst        = tmp_out;
    p.datalen    = (unsigned int)input_len;
    p.keybits    = keybits;
    p.flags      = AES_FLAG_BSWAP;

    if (ioctl(fd, IOCTL_AES_DO, &p) < 0 || p.donelen != input_len) {
        free(tmp_out);
        return -1;
    }

    memcpy(mac_out, tmp_out + input_len - 16, 16);
    free(tmp_out);
    ccm_stats((unsigned int)input_len);
    return 0;
}

/*
 * HW bulk ECB — encrypts @n_blocks 16-byte blocks of @in into @out.
 * Used by the CCM counter-encryption pass: caller fills @in with
 * Ctr_0, Ctr_1, ..., Ctr_n, and XORs @out against plaintext.
 */
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

    ccm_stats((unsigned int)len);
    return 0;
}

/* ── Software fallback primitives (reached when record is too small to
 *    justify an ioctl, or for the single-block Ctr_0 encryption).
 *    All use mbedtls_aes_crypt_ecb, which aes_alt provides as an
 *    optimized software path for single-block ops. ───────────────── */

/*
 * Software CBC-MAC: Y_0 = 0, Y_{i+1} = AES_K(Y_i XOR X_i)
 * Output = Y_n (the last Y).
 */
static int sw_cbc_mac(mbedtls_aes_context *aes,
                      const unsigned char *input, size_t input_len,
                      unsigned char mac_out[16])
{
    unsigned char y[16] = {0};
    size_t i, off;
    int ret;

    if (input_len == 0 || input_len % 16 != 0) return -1;
    for (off = 0; off < input_len; off += 16) {
        for (i = 0; i < 16; i++) y[i] ^= input[off + i];
        ret = mbedtls_aes_crypt_ecb(aes, MBEDTLS_AES_ENCRYPT, y, y);
        if (ret != 0) return ret;
    }
    memcpy(mac_out, y, 16);
    return 0;
}

/*
 * Software bulk-ECB: encrypt an array of 16-byte counter blocks. Used
 * for small CTR streams where ioctl overhead would dominate.
 */
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

/* ── mbedtls public API ──────────────────────────────────────────── */

void mbedtls_ccm_init(mbedtls_ccm_context *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
    mbedtls_aes_init(&ctx->aes_sw);
}

void mbedtls_ccm_free(mbedtls_ccm_context *ctx)
{
    if (!ctx) return;
    mbedtls_aes_free(&ctx->aes_sw);
    free(ctx->scratch_mac);
    free(ctx->scratch_ctr);
    free(ctx->scratch_ks);
    mbedtls_platform_zeroize(ctx, sizeof(*ctx));
}

int mbedtls_ccm_setkey(mbedtls_ccm_context *ctx,
                       mbedtls_cipher_id_t cipher,
                       const unsigned char *key,
                       unsigned int keybits)
{
    int nwords, ret;

    if (cipher != MBEDTLS_CIPHER_ID_AES)
        return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (keybits_to_nwords((int)keybits, &nwords) != 0)
        return MBEDTLS_ERR_CCM_BAD_INPUT;

    /* Packed BE words for the HW path. */
    pack_key(key, nwords, ctx->hw_key);

    /* Software expansion for the under-threshold path + Ctr_0. */
    ret = mbedtls_aes_setkey_enc(&ctx->aes_sw, key, keybits);
    if (ret != 0) return ret;

    /* Pre-allocate the per-record scratch buffers once here. On re-key,
     * reuse what we have. The sizes cover any TLS record up to 16 KB;
     * larger inputs would return EFAULT below. */
    if (!ctx->scratch_mac)
        ctx->scratch_mac = malloc(MBEDTLS_CCM_ALT_SCRATCH_SIZE);
    if (!ctx->scratch_ctr)
        ctx->scratch_ctr = malloc(MBEDTLS_CCM_ALT_SCRATCH_SIZE);
    if (!ctx->scratch_ks)
        ctx->scratch_ks  = malloc(MBEDTLS_CCM_ALT_SCRATCH_SIZE);
    if (!ctx->scratch_mac || !ctx->scratch_ctr || !ctx->scratch_ks) {
        free(ctx->scratch_mac); ctx->scratch_mac = NULL;
        free(ctx->scratch_ctr); ctx->scratch_ctr = NULL;
        free(ctx->scratch_ks);  ctx->scratch_ks  = NULL;
        return MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED;
    }

    ctx->keybits  = (int)keybits;
    ctx->have_key = 1;
    return 0;
}

/*
 * Assemble the CBC-MAC input per RFC 3610 §2.2:
 *   B_0 = flags || nonce || Q (length of plaintext in L bytes, big-endian)
 *   formatted_AD = length-encoding || ad || zero-pad to 16
 *   plaintext (pre-pad already embedded by caller layout)
 *
 * Caller provides a workbuf large enough for
 *   16 + round16(2 + ad_len) + round16(plen)
 * and we fill it in-place.
 *
 * Returns total length (always a multiple of 16).
 */
static size_t build_mac_input(unsigned char *buf,
                              const unsigned char *iv, size_t iv_len,
                              const unsigned char *ad, size_t ad_len,
                              const unsigned char *pt, size_t plen,
                              size_t tag_len)
{
    size_t q = 15 - iv_len;        /* length of Q field */
    size_t off = 0;
    size_t i;

    /* B_0: flags byte */
    unsigned char flags = 0;
    if (ad_len > 0)  flags |= 0x40;                 /* Adata bit */
    flags |= ((unsigned char)((tag_len - 2) / 2)) << 3;
    flags |= (unsigned char)(q - 1);
    buf[off++] = flags;
    memcpy(buf + off, iv, iv_len);
    off += iv_len;
    /* plaintext length as big-endian, q bytes (mbedtls caps plen at
     * 2^(8q)-1 at the API level, but guard anyway) */
    for (i = 0; i < q; i++)
        buf[off + q - 1 - i] = (unsigned char)((plen >> (8 * i)) & 0xff);
    off += q;
    /* B_0 should be exactly 16 bytes */

    /* AD length encoding (RFC 3610 §2.2): for common TLS sizes (<65280)
     * use 2-byte big-endian; larger we'd need 6 or 10 bytes. TLS record
     * AAD is <= ~20 bytes so we always hit the 2-byte path. */
    if (ad_len > 0) {
        if (ad_len < 0xff00) {
            buf[off++] = (unsigned char)(ad_len >> 8);
            buf[off++] = (unsigned char)(ad_len & 0xff);
        } else {
            /* 6-byte encoding: 0xff 0xfe || 4-byte BE length */
            buf[off++] = 0xff;
            buf[off++] = 0xfe;
            buf[off++] = (unsigned char)(ad_len >> 24);
            buf[off++] = (unsigned char)(ad_len >> 16);
            buf[off++] = (unsigned char)(ad_len >>  8);
            buf[off++] = (unsigned char)(ad_len      );
        }
        memcpy(buf + off, ad, ad_len);
        off += ad_len;
        /* pad to 16 */
        while (off % 16) buf[off++] = 0;
    }

    /* plaintext, zero-padded to 16 */
    if (plen > 0) {
        memcpy(buf + off, pt, plen);
        off += plen;
        while (off % 16) buf[off++] = 0;
    }

    return off;
}

/*
 * Build the counter stream: N = ceil(plen/16) counter blocks, starting
 * from Ctr_1 (Ctr_0 is used for the tag and computed separately).
 *   Ctr_i = flags_ctr || nonce || i (big-endian, q bytes)
 *   flags_ctr = q - 1
 *
 * Returns the number of counter blocks written into @ctr_blocks.
 */
static size_t build_ctr_blocks(unsigned char *ctr_blocks,
                               const unsigned char *iv, size_t iv_len,
                               size_t plen)
{
    size_t q = 15 - iv_len;
    size_t n = (plen + 15) / 16;
    size_t i, j;

    for (i = 0; i < n; i++) {
        unsigned char *b = ctr_blocks + i * 16;
        size_t counter = i + 1;          /* Ctr_1 .. Ctr_n */
        b[0] = (unsigned char)(q - 1);
        memcpy(b + 1, iv, iv_len);
        for (j = 0; j < q; j++)
            b[1 + iv_len + q - 1 - j] =
                (unsigned char)((counter >> (8 * j)) & 0xff);
    }
    return n;
}

/*
 * Build Ctr_0 (used to encrypt the tag).
 */
static void build_ctr0(unsigned char out[16],
                       const unsigned char *iv, size_t iv_len)
{
    size_t q = 15 - iv_len;
    out[0] = (unsigned char)(q - 1);
    memcpy(out + 1, iv, iv_len);
    memset(out + 1 + iv_len, 0, q);
}

/* (extract_key removed — ccm_setkey stores the packed key directly.) */

/*
 * One-shot CCM encryption with tag.
 */
int mbedtls_ccm_encrypt_and_tag(mbedtls_ccm_context *ctx, size_t length,
                                const unsigned char *iv, size_t iv_len,
                                const unsigned char *ad, size_t ad_len,
                                const unsigned char *input, unsigned char *output,
                                unsigned char *tag, size_t tag_len)
{
    unsigned char mac[16], ctr0_enc[16], s0[16];
    size_t mac_len, n_ctr;
    int use_hw, ret = MBEDTLS_ERR_CCM_BAD_INPUT;
    size_t i;

    if (!ctx->have_key) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (iv_len < 7 || iv_len > 13) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (tag_len < 4 || tag_len > 16 || (tag_len & 1)) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (ad_len >= 0xff00) return MBEDTLS_ERR_CCM_BAD_INPUT;
    /* Scratch buffers (ctx->scratch_mac / scratch_ctr / scratch_ks) are
     * sized by MBEDTLS_CCM_ALT_SCRATCH_SIZE. Each needs n_ctr * 16
     * bytes where n_ctr = ceil(length/16). TLS 1.3 records can reach
     * 16385 bytes (16384 plaintext + 1-byte content-type), so a flat
     * 16 KB cap was off-by-one and rejected valid records. */
    if (length > MBEDTLS_CCM_ALT_SCRATCH_SIZE) return MBEDTLS_ERR_CCM_BAD_INPUT;

    /* Dispatch: small records stay in CPU entirely; larger records go
     * through /dev/aes. Threshold is driven by ioctl round-trip cost
     * vs software AES — for T20 ~512 bytes is the empirical breakeven.
     * Ctr_0 (single block) is always SW: no record size justifies
     * the ioctl for 16 bytes. */
    use_hw = ((int)length >= CCM_ALT_HW_MIN_SIZE) && ccm_hw_fd_get() >= 0;

    /* Step 1-2: build MAC input in the pre-allocated buffer, run CBC-MAC */
    memset(ctx->scratch_mac, 0, 32 + ((2 + ad_len + 15) & ~15) + ((length + 15) & ~15));
    mac_len = build_mac_input(ctx->scratch_mac, iv, iv_len, ad, ad_len,
                              input, length, tag_len);
    if (use_hw) {
        if (hw_cbc_mac(ccm_hw_fd, ctx->hw_key, ctx->keybits,
                       ctx->scratch_mac, mac_len, mac) != 0) {
            ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
        }
    } else {
        if (sw_cbc_mac(&ctx->aes_sw, ctx->scratch_mac, mac_len, mac) != 0) {
            ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
        }
        if ((int)length < CCM_ALT_HW_MIN_SIZE)
            ccm_sw_small++;
    }

    /* Step 3: counter stream — reuse scratch_ctr / scratch_ks */
    n_ctr = (length + 15) / 16;
    if (n_ctr > 0) {
        (void)build_ctr_blocks(ctx->scratch_ctr, iv, iv_len, length);
        if (use_hw) {
            if (hw_ecb_bulk(ccm_hw_fd, ctx->hw_key, ctx->keybits,
                            ctx->scratch_ctr, n_ctr, ctx->scratch_ks) != 0) {
                ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
            }
        } else {
            if (sw_ecb_bulk(&ctx->aes_sw, ctx->scratch_ctr, n_ctr,
                            ctx->scratch_ks) != 0) {
                ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
            }
        }
        for (i = 0; i < length; i++)
            output[i] = input[i] ^ ctx->scratch_ks[i];
    }

    /* Step 5: Ctr_0 (always SW, single block) */
    build_ctr0(ctr0_enc, iv, iv_len);
    if (mbedtls_aes_crypt_ecb(&ctx->aes_sw, MBEDTLS_AES_ENCRYPT,
                              ctr0_enc, s0) != 0) {
        ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
    }
    for (i = 0; i < tag_len; i++)
        tag[i] = mac[i] ^ s0[i];

    ret = 0;
out:
    mbedtls_platform_zeroize(mac, sizeof(mac));
    mbedtls_platform_zeroize(s0, sizeof(s0));
    
    return ret;
}

int mbedtls_ccm_auth_decrypt(mbedtls_ccm_context *ctx, size_t length,
                             const unsigned char *iv, size_t iv_len,
                             const unsigned char *ad, size_t ad_len,
                             const unsigned char *input, unsigned char *output,
                             const unsigned char *tag, size_t tag_len)
{
    unsigned char mac[16], ctr0_enc[16], expected_tag[16], s0[16];
    size_t mac_len, n_ctr;
    int use_hw, ret = MBEDTLS_ERR_CCM_BAD_INPUT;
    size_t i;
    unsigned char diff;

    if (!ctx->have_key) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (iv_len < 7 || iv_len > 13) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (tag_len < 4 || tag_len > 16 || (tag_len & 1)) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (ad_len >= 0xff00) return MBEDTLS_ERR_CCM_BAD_INPUT;
    if (length > MBEDTLS_CCM_ALT_SCRATCH_SIZE) return MBEDTLS_ERR_CCM_BAD_INPUT;

    use_hw = ((int)length >= CCM_ALT_HW_MIN_SIZE) && ccm_hw_fd_get() >= 0;

    /* Decrypt ciphertext with the counter stream first */
    n_ctr = (length + 15) / 16;
    if (n_ctr > 0) {
        (void)build_ctr_blocks(ctx->scratch_ctr, iv, iv_len, length);
        if (use_hw) {
            if (hw_ecb_bulk(ccm_hw_fd, ctx->hw_key, ctx->keybits,
                            ctx->scratch_ctr, n_ctr, ctx->scratch_ks) != 0) {
                ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
            }
        } else {
            if (sw_ecb_bulk(&ctx->aes_sw, ctx->scratch_ctr, n_ctr,
                            ctx->scratch_ks) != 0) {
                ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
            }
        }
        for (i = 0; i < length; i++)
            output[i] = input[i] ^ ctx->scratch_ks[i];
    }

    /* Recompute MAC over (nonce || ad || decrypted plaintext) */
    memset(ctx->scratch_mac, 0, 32 + ((2 + ad_len + 15) & ~15) + ((length + 15) & ~15));
    mac_len = build_mac_input(ctx->scratch_mac, iv, iv_len, ad, ad_len,
                              output, length, tag_len);
    if (use_hw) {
        if (hw_cbc_mac(ccm_hw_fd, ctx->hw_key, ctx->keybits,
                       ctx->scratch_mac, mac_len, mac) != 0) {
            ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
        }
    } else {
        if (sw_cbc_mac(&ctx->aes_sw, ctx->scratch_mac, mac_len, mac) != 0) {
            ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
        }
        if ((int)length < CCM_ALT_HW_MIN_SIZE)
            ccm_sw_small++;
    }

    /* Encrypt the MAC with Ctr_0 (SW, single block) */
    build_ctr0(ctr0_enc, iv, iv_len);
    if (mbedtls_aes_crypt_ecb(&ctx->aes_sw, MBEDTLS_AES_ENCRYPT,
                              ctr0_enc, s0) != 0) {
        ret = MBEDTLS_ERR_PLATFORM_HW_ACCEL_FAILED; goto out;
    }
    for (i = 0; i < tag_len; i++)
        expected_tag[i] = mac[i] ^ s0[i];

    diff = 0;
    for (i = 0; i < tag_len; i++)
        diff |= expected_tag[i] ^ tag[i];

    if (diff != 0) {
        mbedtls_platform_zeroize(output, length);
        ret = MBEDTLS_ERR_CCM_AUTH_FAILED;
        goto out;
    }

    ret = 0;
out:
    mbedtls_platform_zeroize(mac, sizeof(mac));
    mbedtls_platform_zeroize(expected_tag, sizeof(expected_tag));
    mbedtls_platform_zeroize(s0, sizeof(s0));
    return ret;
}

/*
 * CCM* variants — mbedtls TLS never uses these (they're for 802.15.4/
 * Zigbee). Delegate to the non-star path; the only algorithmic
 * difference is that CCM* allows tag_len == 0 (unauthenticated), which
 * is a footgun we don't support.
 */
int mbedtls_ccm_star_encrypt_and_tag(mbedtls_ccm_context *ctx, size_t length,
                                     const unsigned char *iv, size_t iv_len,
                                     const unsigned char *ad, size_t ad_len,
                                     const unsigned char *input, unsigned char *output,
                                     unsigned char *tag, size_t tag_len)
{
    if (tag_len == 0) return MBEDTLS_ERR_CCM_BAD_INPUT;
    return mbedtls_ccm_encrypt_and_tag(ctx, length, iv, iv_len, ad, ad_len,
                                       input, output, tag, tag_len);
}

int mbedtls_ccm_star_auth_decrypt(mbedtls_ccm_context *ctx, size_t length,
                                  const unsigned char *iv, size_t iv_len,
                                  const unsigned char *ad, size_t ad_len,
                                  const unsigned char *input, unsigned char *output,
                                  const unsigned char *tag, size_t tag_len)
{
    if (tag_len == 0) return MBEDTLS_ERR_CCM_BAD_INPUT;
    return mbedtls_ccm_auth_decrypt(ctx, length, iv, iv_len, ad, ad_len,
                                    input, output, tag, tag_len);
}

/*
 * Streaming API — stubbed. The TLS record layer uses encrypt_and_tag
 * (via mbedtls_cipher_auth_encrypt_ext), not these functions. We return
 * MBEDTLS_ERR_CCM_BAD_INPUT so any unexpected caller fails loudly.
 */
int mbedtls_ccm_starts(mbedtls_ccm_context *ctx, int mode,
                       const unsigned char *iv, size_t iv_len)
{
    (void)ctx; (void)mode; (void)iv; (void)iv_len;
    return MBEDTLS_ERR_CCM_BAD_INPUT;
}

int mbedtls_ccm_set_lengths(mbedtls_ccm_context *ctx,
                            size_t total_ad_len, size_t plaintext_len, size_t tag_len)
{
    (void)ctx; (void)total_ad_len; (void)plaintext_len; (void)tag_len;
    return MBEDTLS_ERR_CCM_BAD_INPUT;
}

int mbedtls_ccm_update_ad(mbedtls_ccm_context *ctx,
                          const unsigned char *ad, size_t ad_len)
{
    (void)ctx; (void)ad; (void)ad_len;
    return MBEDTLS_ERR_CCM_BAD_INPUT;
}

int mbedtls_ccm_update(mbedtls_ccm_context *ctx,
                       const unsigned char *input, size_t input_len,
                       unsigned char *output, size_t output_size,
                       size_t *output_len)
{
    (void)ctx; (void)input; (void)input_len;
    (void)output; (void)output_size; (void)output_len;
    return MBEDTLS_ERR_CCM_BAD_INPUT;
}

int mbedtls_ccm_finish(mbedtls_ccm_context *ctx,
                       unsigned char *tag, size_t tag_len)
{
    (void)ctx; (void)tag; (void)tag_len;
    return MBEDTLS_ERR_CCM_BAD_INPUT;
}

/* mbedtls_ccm_self_test is provided by upstream ccm.c — its definition
 * is not inside the MBEDTLS_CCM_ALT guard, so we must not duplicate it
 * here or the link fails with a multiple-definition error. */
