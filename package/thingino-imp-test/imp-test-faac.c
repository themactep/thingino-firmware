/*
 * imp-test-faac - FAAC encoder crash reproducer with MIPS FCSR diagnostics
 *
 * Feeds silent/quiet PCM into FAAC using the same configuration
 * as prudynt to reproduce the SIGFPE crash in libfaac.
 *
 * No IMP dependency — runs on host or target.
 *
 * Usage:
 *   imp-test-faac [-r rate] [-b bitrate] [-n frames] [-s] [-f]
 *
 * Options:
 *   -r <rate>     Sample rate (default: 48000)
 *   -b <bitrate>  Bitrate in kbps (default: 128)
 *   -c <channels> Channels (default: 1)
 *   -n <frames>   Frames to encode (default: 50)
 *   -s            Use silence (all zeros) instead of low noise
 *   -f            Clear FPU exception enable bits before encoding
 *   -h            Help
 *
 * Exit codes:
 *   0   OK, no crash
 *   1   Usage error
 *   2   faacEncOpen failed
 *   3   faacEncSetConfiguration failed
 *   4   malloc failed
 *   20  SIGFPE caught
 */

#include <faac.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ---- MIPS FPU Control/Status Register (FCSR) helpers ----
 *
 * FCSR layout (coprocessor 1, register 31):
 *   Bits  1:0  - Rounding mode (0=nearest, 1=zero, 2=+inf, 3=-inf)
 *   Bits  6:2  - Flag bits (sticky): Inexact, Underflow, Overflow, DivByZero, InvalidOp
 *   Bits 11:7  - Enable bits:        Inexact, Underflow, Overflow, DivByZero, InvalidOp
 *   Bits 17:12 - Cause bits:         Inexact, Underflow, Overflow, DivByZero, InvalidOp, Unimplemented
 *   Bit  23    - FS (flush denorms to zero)
 *   Bit  24    - FO (flush denorms to zero, output)
 */
#ifdef __mips__

#define FCSR_ENABLE_INEXACT   (1 << 7)
#define FCSR_ENABLE_UNDERFLOW (1 << 8)
#define FCSR_ENABLE_OVERFLOW  (1 << 9)
#define FCSR_ENABLE_DIVZERO   (1 << 10)
#define FCSR_ENABLE_INVALID   (1 << 11)
#define FCSR_ENABLE_ALL       0x0F80
#define FCSR_FLAG_ALL         0x007C
#define FCSR_CAUSE_ALL        0x3F000

static unsigned int fcsr_read(void) {
	unsigned int val;
	__asm__ volatile("cfc1 %0, $31" : "=r"(val));
	return val;
}

static void fcsr_write(unsigned int val) {
	__asm__ volatile("ctc1 %0, $31" : : "r"(val));
}

static void fcsr_dump(const char *label) {
	unsigned int f = fcsr_read();
	fprintf(stderr, "[imp-test-faac] FCSR %s: 0x%08x\n", label, f);
	fprintf(stderr, "  rounding=%u  FS=%u\n", f & 3, (f >> 23) & 1);
	fprintf(stderr, "  enables: I=%u U=%u O=%u Z=%u V=%u (raw 0x%03x)\n",
		!!(f & FCSR_ENABLE_INEXACT), !!(f & FCSR_ENABLE_UNDERFLOW),
		!!(f & FCSR_ENABLE_OVERFLOW), !!(f & FCSR_ENABLE_DIVZERO),
		!!(f & FCSR_ENABLE_INVALID), (f & FCSR_ENABLE_ALL) >> 7);
	fprintf(stderr, "  flags:   I=%u U=%u O=%u Z=%u V=%u\n",
		!!(f & (1<<2)), !!(f & (1<<3)), !!(f & (1<<4)),
		!!(f & (1<<5)), !!(f & (1<<6)));
	fprintf(stderr, "  causes:  I=%u U=%u O=%u Z=%u V=%u E=%u\n",
		!!(f & (1<<12)), !!(f & (1<<13)), !!(f & (1<<14)),
		!!(f & (1<<15)), !!(f & (1<<16)), !!(f & (1<<17)));
}

static void fcsr_clear_enables(void) {
	unsigned int f = fcsr_read();
	f &= ~FCSR_ENABLE_ALL;
	f &= ~FCSR_CAUSE_ALL;
	fcsr_write(f);
}

#else /* not MIPS */

static void fcsr_dump(const char *label) {
	fprintf(stderr, "[imp-test-faac] FCSR %s: (not MIPS, skipped)\n", label);
}
static void fcsr_clear_enables(void) {}

#endif /* __mips__ */

static void fpe_handler(int sig) {
	(void)sig;
#ifdef __mips__
	fcsr_dump("at-crash");
#endif
	fprintf(stderr, "[imp-test-faac] CAUGHT SIGFPE — FAAC crashed!\n");
	fprintf(stderr, "[imp-test-faac] This confirms the FAAC encoder bug.\n");
	_exit(20);
}

int main(int argc, char *argv[]) {
	int sample_rate = 48000;
	int bitrate_kbps = 128;
	int num_channels = 1;
	int max_frames = 50;
	int use_silence = 0;
	int fix_fcsr = 0;
	int opt;

	while ((opt = getopt(argc, argv, "r:b:c:n:sfh")) != -1) {
		switch (opt) {
		case 'r': sample_rate = atoi(optarg); break;
		case 'b': bitrate_kbps = atoi(optarg); break;
		case 'c': num_channels = atoi(optarg); break;
		case 'n': max_frames = atoi(optarg); break;
		case 's': use_silence = 1; break;
		case 'f': fix_fcsr = 1; break;
		case 'h': /* fall through */
		default:
			fprintf(stderr,
				"Usage: %s [-r rate] [-b kbps] [-c chans] [-n frames] [-s] [-f]\n"
				"  -s  Use silence (all zeros)\n"
				"  -f  Clear MIPS FPU exception enable bits before encoding\n",
				argv[0]);
			return 1;
		}
	}

	signal(SIGFPE, fpe_handler);

	fprintf(stderr, "[imp-test-faac] config: rate=%d bitrate=%dkbps channels=%d frames=%d silence=%d fix_fcsr=%d\n",
		sample_rate, bitrate_kbps, num_channels, max_frames, use_silence, fix_fcsr);

	fcsr_dump("at-startup");

	/* Open FAAC encoder — same as prudynt's AACEncoder::open() */
	unsigned long input_samples = 0;
	unsigned long output_buffer_size = 0;

	faacEncHandle handle = faacEncOpen(sample_rate, num_channels,
		&input_samples, &output_buffer_size);
	if (!handle) {
		fprintf(stderr, "[imp-test-faac] FAIL: faacEncOpen returned NULL\n");
		return 2;
	}

	fprintf(stderr, "[imp-test-faac] faacEncOpen OK: inputSamples=%lu outputBufferSize=%lu\n",
		input_samples, output_buffer_size);
	fcsr_dump("after-open");

	/* Configure — same as prudynt */
	faacEncConfigurationPtr config = faacEncGetCurrentConfiguration(handle);
	config->aacObjectType = LOW;
	config->bandWidth = sample_rate;
	config->bitRate = bitrate_kbps * 1000;
	config->inputFormat = FAAC_INPUT_16BIT;
	config->mpegVersion = MPEG4;
	config->outputFormat = 0; /* RAW_STREAM */
	config->allowMidside = 0;
	config->useTns = 0;

	if (!faacEncSetConfiguration(handle, config)) {
		fprintf(stderr, "[imp-test-faac] FAIL: faacEncSetConfiguration failed\n");
		faacEncClose(handle);
		return 3;
	}
	fprintf(stderr, "[imp-test-faac] configured: bitRate=%ld bandWidth=%d\n",
		config->bitRate, config->bandWidth);
	fcsr_dump("after-config");

	/* Allocate buffers */
	int16_t *pcm = (int16_t *)calloc(input_samples, sizeof(int16_t));
	unsigned char *outbuf = (unsigned char *)malloc(output_buffer_size);
	if (!pcm || !outbuf) {
		fprintf(stderr, "[imp-test-faac] FAIL: malloc\n");
		return 4;
	}

	if (!use_silence) {
		/* Fill with very low-level noise (like a quiet mic) */
		srand(42);
		for (unsigned long i = 0; i < input_samples; i++)
			pcm[i] = (int16_t)((rand() % 16) - 8);
	}

	if (fix_fcsr) {
		fprintf(stderr, "[imp-test-faac] clearing FCSR exception enable bits\n");
		fcsr_clear_enables();
		fcsr_dump("after-fix");
	}

	fprintf(stderr, "[imp-test-faac] --- encoding %d frames (inputSamples=%lu per frame) ---\n",
		max_frames, input_samples);

	int total_bytes = 0;
	for (int i = 0; i < max_frames; i++) {
		int len = faacEncEncode(handle, (int32_t *)pcm, input_samples,
			outbuf, output_buffer_size);

		if (len < 0) {
			fprintf(stderr, "[imp-test-faac] ERROR: faacEncEncode returned %d at frame %d\n", len, i);
			fcsr_dump("after-error");
			break;
		}

		total_bytes += len;
		if (i < 5 || (i % 10 == 0)) {
			fprintf(stderr, "[imp-test-faac] frame %d: encoded %d bytes (total %d)\n",
				i, len, total_bytes);
		}

		/* Dump FCSR on first few frames to catch when flags appear */
		if (i < 3) {
			fcsr_dump("encode-loop");
		}
	}

	fcsr_dump("after-encode");
	fprintf(stderr, "[imp-test-faac] --- done: %d total bytes encoded ---\n", total_bytes);

	faacEncClose(handle);
	free(pcm);
	free(outbuf);

	fprintf(stderr, "[imp-test-faac] OK: no crash\n");
	return 0;
}
