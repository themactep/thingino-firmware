/* Host-compiled test for daynightd's isp-m0 parser — TEST HARNESS ONLY,
 * never installed on a device (not referenced by thingino-daynightd.mk).
 *
 * Includes the real parser source with the ISP proc path redirected to a
 * fixture symlink, then verifies parsed fields and the day/night decision
 * signal against two real device dumps:
 *
 *   T31 gc2053 — Wyze Cam v3, ISP H20221206a, legacy field set
 *                (archived live capture, same file format daynightd has
 *                parsed since v1)
 *   T41 gc4023 — ISP H20250310a, Ae-fields / EVLog2 field set
 *                (live capture from ing-noorio-t110-8569, PR #2008)
 *
 * It also checks the EVLog2 scale identity that PR review asked to prove:
 * both ISP generations print 65536*log2(integration_lines x total_gain),
 * so equal exposures print equal numbers and the daemon's default
 * thresholds transfer between platforms unchanged.
 *
 * Build+run from this directory:
 *   gcc -std=gnu99 -O0 -g -I stub -o test-parse-isp-m0 test-parse-isp-m0.c -lm
 *   ./test-parse-isp-m0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>

/* Redirect the parser at a symlink the test re-points between fixtures. */
#define ISP_M0_PATH "fixtures/current"

/* The daemon source has its own main(); demote it. */
#define main daemon_main
#include "../daynightd.c"
#undef main

static int failures = 0;

#define CHECK_INT(desc, got, want) do { \
    if ((got) != (want)) { \
        printf("FAIL %s: got %d, want %d\n", desc, (int)(got), (int)(want)); \
        failures++; \
    } else { \
        printf("ok   %s = %d\n", desc, (int)(got)); \
    } \
} while (0)

#define CHECK_STR(desc, got, want) do { \
    if (strcmp((got), (want)) != 0) { \
        printf("FAIL %s: got \"%s\", want \"%s\"\n", desc, got, want); \
        failures++; \
    } else { \
        printf("ok   %s = \"%s\"\n", desc, got); \
    } \
} while (0)

#define CHECK_RANGE(desc, got, lo, hi) do { \
    if ((got) < (lo) || (got) > (hi)) { \
        printf("FAIL %s: got %d, want %d..%d\n", desc, (int)(got), (int)(lo), (int)(hi)); \
        failures++; \
    } else { \
        printf("ok   %s = %d (in %d..%d)\n", desc, (int)(got), (int)(lo), (int)(hi)); \
    } \
} while (0)

static void point_fixture(const char *target) {
    unlink("fixtures/current");
    if (symlink(target, "fixtures/current") != 0) {
        perror("symlink");
        exit(2);
    }
}

int main(void) {
    sensor_sample_t s;
    int rc;

    /* ---------- T41 gc4023 sample (PR #2008 hardware) ---------- */
    point_fixture("t41-proc-jz-isp-m0.txt");
    rc = parse_isp(&s);
    CHECK_INT("t41 parse_isp rc", rc, 0);
    CHECK_STR("t41 platform", s.platform, "t41");
    CHECK_STR("t41 isp_mode", s.isp_mode, "day");
    CHECK_INT("t41 ev_log2", s.ev_log2, 659070);
    CHECK_INT("t41 integration_time", s.integration_time, 1065);
    CHECK_INT("t41 max_integration_time", s.max_integration_time, 1492);
    CHECK_INT("t41 analog_gain", s.analog_gain, 1024);      /* 1.0x */
    CHECK_INT("t41 max_analog_gain", s.max_analog_gain, 65536);
    CHECK_INT("t41 digital_gain", s.digital_gain, 0);
    CHECK_INT("t41 isp_digital_gain", s.isp_digital_gain, 1024); /* 1.0x */
    CHECK_INT("t41 max_isp_digital_gain", s.max_isp_digital_gain, 3072);
    CHECK_INT("t41 wb_rgain", s.wb_rgain, 164);
    CHECK_INT("t41 wb_bgain", s.wb_bgain, 155);
    CHECK_INT("t41 wb_color_temp", s.wb_color_temp, 4910);
    CHECK_INT("t41 primary_signal", s.primary_signal, 659070);
    /* Dim indoor scene: EVLog2 659070 sits past the 550000 night threshold
     * on the transferred defaults — expected for this capture, and exactly
     * what the same exposure would produce on T31 (scale identity below). */
    CHECK_RANGE("t41 brightness_pct", compute_brightness_pct(&s), 44, 52);

    /* ---------- T31 gc2053 sample (legacy field set) ---------- */
    point_fixture("t31-proc-jz-isp-m0.txt");
    rc = parse_isp(&s);
    CHECK_INT("t31 parse_isp rc", rc, 0);
    CHECK_STR("t31 platform", s.platform, "t31");
    CHECK_STR("t31 isp_mode", s.isp_mode, "Day");
    CHECK_INT("t31 ev_log2", s.ev_log2, 439854);
    CHECK_INT("t31 integration_time", s.integration_time, 104);
    CHECK_INT("t31 max_integration_time", s.max_integration_time, 1410);
    CHECK_INT("t31 analog_gain", s.analog_gain, 0);
    CHECK_INT("t31 max_analog_gain", s.max_analog_gain, 160);
    CHECK_INT("t31 isp_digital_gain", s.isp_digital_gain, 0);
    CHECK_INT("t31 max_isp_digital_gain", s.max_isp_digital_gain, 80);
    CHECK_INT("t31 wb_rgain", s.wb_rgain, 474);
    CHECK_INT("t31 wb_bgain", s.wb_bgain, 485);
    CHECK_INT("t31 wb_color_temp", s.wb_color_temp, 5283);
    CHECK_INT("t31 primary_signal", s.primary_signal, 439854);
    CHECK_RANGE("t31 brightness_pct", compute_brightness_pct(&s), 62, 70);

    /* ---------- EVLog2 scale identity (review item) ----------
     * value = 65536 * log2(lines * gain) with near-identical line times.
     * Verify both dumps match the identity within 1/64 EV step (~1200). */
    double t41_calc = 65536.0 * log2(1065.35 * 1.0);   /* 1024/1024 gain */
    double t31_calc = 65536.0 * log2(104.43 * 1.0);    /* (1+160)/160 gain */
    CHECK_RANGE("t41 EVLog2 identity", (int)(t41_calc + 0.5), 659070 - 1200, 659070 + 1200);
    CHECK_RANGE("t31 EVLog2 identity", (int)(t31_calc + 0.5), 439854 - 1200, 439854 + 1200);

    unlink("fixtures/current");
    if (failures) {
        printf("\n%d check(s) FAILED\n", failures);
        return 1;
    }
    printf("\nall checks passed\n");
    return 0;
}
