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
 *   2   faac_encoder_open failed
 *   3   faac_encoder_get_info failed
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

	/* Open FAAC encoder - same as prudynt's AACEncoder::open() */
	faac_params params;
	faac_status st = faac_params_init(&params, (uint32_t)sizeof(params));
	if (st != FAAC_OK) {
		fprintf(stderr, "[imp-test-faac] FAIL: faac_params_init: %s\n",
			faac_strerror(st));
		return 2;
	}

	params.sample_rate = (uint32_t)sample_rate;
	params.channels = (uint32_t)num_channels;
	params.object_type = FAAC_OBJ_LC;
	params.input_format = FAAC_INPUT_16BIT;
	params.stream_format = FAAC_STREAM_RAW;
	params.bit_rate = (uint32_t)bitrate_kbps * 1000 * (uint32_t)num_channels;
	params.bandwidth = (uint32_t)sample_rate;
	params.flags &= ~FAAC_FLAG_TNS;
	params.stereo_mode = FAAC_STEREO_LR;

	faac_encoder *handle = NULL;
	st = faac_encoder_open(&params, &handle);
	if (st != FAAC_OK) {
		fprintf(stderr, "[imp-test-faac] FAIL: faac_encoder_open: %s\n",
			faac_strerror(st));
		return 2;
	}

	faac_encoder_info info;
	info.struct_size = (uint32_t)sizeof(info);
	st = faac_encoder_get_info(handle, &info);
	if (st != FAAC_OK) {
		fprintf(stderr, "[imp-test-faac] FAIL: faac_encoder_get_info: %s\n",
			faac_strerror(st));
		faac_encoder_close(&handle);
		return 3;
	}

	uint32_t input_samples = info.frame_samples * params.channels;
	uint32_t output_buffer_size = info.max_output_bytes;

	fprintf(stderr, "[imp-test-faac] faac_encoder_open OK: inputSamples=%u outputBufferSize=%u\n",
		input_samples, output_buffer_size);
	fcsr_dump("after-open");

	fprintf(stderr, "[imp-test-faac] configured: bitRate=%u bandWidth=%u\n",
		params.bit_rate, params.bandwidth);
	fcsr_dump("after-config");

	/* Allocate buffers */
	int16_t *pcm = (int16_t *)calloc(input_samples, sizeof(int16_t));
	unsigned char *outbuf = (unsigned char *)malloc(output_buffer_size);
	if (!pcm || !outbuf) {
		fprintf(stderr, "[imp-test-faac] FAIL: malloc\n");
		faac_encoder_close(&handle);
		free(pcm);
		free(outbuf);
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

	fprintf(stderr, "[imp-test-faac] --- encoding %d frames (inputSamples=%u per frame) ---\n",
		max_frames, input_samples);

	int total_bytes = 0;
	for (int i = 0; i < max_frames; i++) {
		uint32_t len = 0;
		st = faac_encoder_encode(handle, pcm, input_samples,
			outbuf, output_buffer_size, &len);

		if (st != FAAC_OK) {
			fprintf(stderr, "[imp-test-faac] ERROR: faac_encoder_encode: %s at frame %d\n",
				faac_strerror(st), i);
			fcsr_dump("after-error");
			break;
		}

		total_bytes += (int)len;
		if (i < 5 || (i % 10 == 0)) {
			fprintf(stderr, "[imp-test-faac] frame %d: encoded %u bytes (total %d)\n",
				i, len, total_bytes);
		}

		/* Dump FCSR on first few frames to catch when flags appear */
		if (i < 3) {
			fcsr_dump("encode-loop");
		}
	}

	fcsr_dump("after-encode");
	fprintf(stderr, "[imp-test-faac] --- done: %d total bytes encoded ---\n", total_bytes);

	faac_encoder_close(&handle);
	free(pcm);
	free(outbuf);

	fprintf(stderr, "[imp-test-faac] OK: no crash\n");
	return 0;
}
