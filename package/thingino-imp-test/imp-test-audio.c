/*
 * imp-test-audio - Minimal IMP audio capture test
 *
 * Tests the Ingenic IMP audio input subsystem in isolation,
 * without any of the prudynt streaming/encoding machinery.
 *
 * Usage:
 *   imp-test-audio [options]
 *
 * Options:
 *   -r <rate>    Sample rate: 8000,16000,24000,32000,44100,48000 (default: 16000)
 *   -n <frames>  Number of frames to capture (default: 100, 0 = infinite)
 *   -d <devId>   Audio device ID (default: 1, analog MIC)
 *   -c <chn>     Audio input channel (default: 0)
 *   -v <vol>     Volume [-30..120] (default: 80)
 *   -g <gain>    Gain [-1 = skip, 0..31] (default: -1)
 *   -D <depth>   User frame depth (default: 30)
 *   -o <file>    Output raw PCM to file (default: none, discard)
 *   -t <ms>      Polling timeout in ms (default: 1000)
 *   -h           Show this help
 *
 * Exit codes:
 *   0  All frames captured successfully
 *   1  Argument error
 *   2  IMP_System_Init failed
 *   3  IMP_AI_SetPubAttr failed
 *   4  IMP_AI_Enable failed
 *   5  IMP_AI_SetChnParam failed
 *   6  IMP_AI_EnableChn failed
 *   7  IMP_AI_SetVol failed
 *   8  IMP_AI_SetGain failed
 *   9  IMP_AI_PollingFrame failed (after retries)
 *  10  IMP_AI_GetFrame failed
 *
 * Build: see thingino-imp-test.mk
 */

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* ---- Minimal IMP type/function declarations ----
 * Copied from the Ingenic SDK imp_audio.h / imp_system.h.
 * Only what this test needs; keeps it dependency-free.
 */

#ifdef __cplusplus
extern "C" {
#endif

/* imp_system */
int IMP_System_Init(void);
int IMP_System_Exit(void);

/* Audio sample rates */
typedef enum {
	AUDIO_SAMPLE_RATE_8000  = 8000,
	AUDIO_SAMPLE_RATE_16000 = 16000,
	AUDIO_SAMPLE_RATE_24000 = 24000,
	AUDIO_SAMPLE_RATE_32000 = 32000,
	AUDIO_SAMPLE_RATE_44100 = 44100,
	AUDIO_SAMPLE_RATE_48000 = 48000,
	AUDIO_SAMPLE_RATE_96000 = 96000,
} IMPAudioSampleRate;

typedef enum {
	AUDIO_BIT_WIDTH_16 = 16,
} IMPAudioBitWidth;

typedef enum {
	AUDIO_SOUND_MODE_MONO   = 1,
	AUDIO_SOUND_MODE_STEREO = 2,
} IMPAudioSoundMode;

typedef enum {
	IMP_BLOCK   = 0,
	IMP_NOBLOCK = 1,
} IMPBlock;

typedef struct {
	IMPAudioSampleRate samplerate;
	IMPAudioBitWidth   bitwidth;
	IMPAudioSoundMode  soundmode;
	int frmNum;
	int numPerFrm;
	int chnCnt;
} IMPAudioIOAttr;

typedef struct {
	IMPAudioBitWidth  bitwidth;
	IMPAudioSoundMode soundmode;
	uint32_t *virAddr;
	uint32_t  phyAddr;
	int64_t   timeStamp;
	int       seq;
	int       len;
} IMPAudioFrame;

typedef struct {
	int usrFrmDepth;
	int Rev;
} IMPAudioIChnParam;

/* Audio input API */
int IMP_AI_SetPubAttr(int audioDevId, IMPAudioIOAttr *attr);
int IMP_AI_GetPubAttr(int audioDevId, IMPAudioIOAttr *attr);
int IMP_AI_Enable(int audioDevId);
int IMP_AI_Disable(int audioDevId);
int IMP_AI_EnableChn(int audioDevId, int aiChn);
int IMP_AI_DisableChn(int audioDevId, int aiChn);
int IMP_AI_SetChnParam(int audioDevId, int aiChn, IMPAudioIChnParam *chnParam);
int IMP_AI_GetChnParam(int audioDevId, int aiChn, IMPAudioIChnParam *chnParam);
int IMP_AI_SetVol(int audioDevId, int aiChn, int aiVol);
int IMP_AI_GetVol(int audioDevId, int aiChn, int *aiVol);
int IMP_AI_SetGain(int audioDevId, int aiChn, int aiGain);
int IMP_AI_GetGain(int audioDevId, int aiChn, int *aiGain);
int IMP_AI_PollingFrame(int audioDevId, int aiChn, unsigned int timeout_ms);
int IMP_AI_GetFrame(int audioDevId, int aiChn, IMPAudioFrame *frm, IMPBlock block);
int IMP_AI_ReleaseFrame(int audioDevId, int aiChn, IMPAudioFrame *frm);

#ifdef __cplusplus
}
#endif

/* ---- end IMP declarations ---- */

static volatile sig_atomic_t g_quit = 0;

static void sig_handler(int sig) {
	(void)sig;
	g_quit = 1;
}

static void usage(const char *prog) {
	fprintf(stderr,
		"Usage: %s [options]\n"
		"  -r <rate>    Sample rate (default: 16000)\n"
		"  -n <frames>  Frames to capture (default: 100, 0=infinite)\n"
		"  -d <devId>   Audio device ID (default: 1)\n"
		"  -c <chn>     Audio channel (default: 0)\n"
		"  -v <vol>     Volume [-30..120] (default: 80)\n"
		"  -g <gain>    Gain [0..31, -1=skip] (default: -1)\n"
		"  -D <depth>   Frame buffer depth (default: 30)\n"
		"  -o <file>    Output raw PCM to file (- for stdout)\n"
		"  -t <ms>      Polling timeout ms (default: 1000)\n"
		"  -h           Help\n", prog);
}

int main(int argc, char *argv[]) {
	int sample_rate = 16000;
	int max_frames  = 100;
	int dev_id      = 1;
	int chn_id      = 0;
	int volume      = 80;
	int gain        = -1;
	int frm_depth   = 30;
	int timeout_ms  = 1000;
	const char *outpath = NULL;
	FILE *outfile   = NULL;
	int opt;

	while ((opt = getopt(argc, argv, "r:n:d:c:v:g:D:o:t:h")) != -1) {
		switch (opt) {
		case 'r': sample_rate = atoi(optarg); break;
		case 'n': max_frames  = atoi(optarg); break;
		case 'd': dev_id      = atoi(optarg); break;
		case 'c': chn_id      = atoi(optarg); break;
		case 'v': volume      = atoi(optarg); break;
		case 'g': gain        = atoi(optarg); break;
		case 'D': frm_depth   = atoi(optarg); break;
		case 'o': outpath     = optarg;        break;
		case 't': timeout_ms  = atoi(optarg); break;
		case 'h': /* fall through */
		default:
			usage(argv[0]);
			return 1;
		}
	}

	signal(SIGINT,  sig_handler);
	signal(SIGTERM, sig_handler);

	fprintf(stderr, "[imp-test-audio] config: dev=%d chn=%d rate=%d vol=%d gain=%d depth=%d timeout=%dms frames=%d\n",
		dev_id, chn_id, sample_rate, volume, gain, frm_depth, timeout_ms,
		max_frames);

	if (outpath) {
		if (strcmp(outpath, "-") == 0) {
			outfile = stdout;
		} else {
			outfile = fopen(outpath, "wb");
			if (!outfile) {
				fprintf(stderr, "[imp-test-audio] ERROR: cannot open %s: %s\n",
					outpath, strerror(errno));
				return 1;
			}
		}
	}

	/* Step 1: IMP_System_Init */
	fprintf(stderr, "[imp-test-audio] IMP_System_Init...\n");
	int ret = IMP_System_Init();
	if (ret != 0) {
		fprintf(stderr, "[imp-test-audio] FAIL: IMP_System_Init returned %d (errno=%d %s)\n",
			ret, errno, strerror(errno));
		return 2;
	}
	fprintf(stderr, "[imp-test-audio] OK: IMP_System_Init\n");

	/* Step 2: IMP_AI_SetPubAttr */
	IMPAudioIOAttr ioattr;
	memset(&ioattr, 0, sizeof(ioattr));
	ioattr.samplerate = (IMPAudioSampleRate)sample_rate;
	ioattr.bitwidth   = AUDIO_BIT_WIDTH_16;
	ioattr.soundmode  = AUDIO_SOUND_MODE_MONO;
	ioattr.frmNum     = 30;
	ioattr.numPerFrm  = sample_rate * 40 / 1000; /* 40ms per frame */
	ioattr.chnCnt     = 1;

	fprintf(stderr, "[imp-test-audio] IMP_AI_SetPubAttr(dev=%d, rate=%d, numPerFrm=%d)...\n",
		dev_id, sample_rate, ioattr.numPerFrm);
	ret = IMP_AI_SetPubAttr(dev_id, &ioattr);
	if (ret != 0) {
		fprintf(stderr, "[imp-test-audio] FAIL: IMP_AI_SetPubAttr returned %d (errno=%d %s)\n",
			ret, errno, strerror(errno));
		IMP_System_Exit();
		return 3;
	}
	fprintf(stderr, "[imp-test-audio] OK: IMP_AI_SetPubAttr\n");

	/* Readback to confirm */
	IMPAudioIOAttr readback;
	memset(&readback, 0, sizeof(readback));
	ret = IMP_AI_GetPubAttr(dev_id, &readback);
	if (ret == 0) {
		fprintf(stderr, "[imp-test-audio] readback: rate=%d bitwidth=%d soundmode=%d frmNum=%d numPerFrm=%d chnCnt=%d\n",
			readback.samplerate, readback.bitwidth, readback.soundmode,
			readback.frmNum, readback.numPerFrm, readback.chnCnt);
	}

	/* Step 3: IMP_AI_Enable */
	fprintf(stderr, "[imp-test-audio] IMP_AI_Enable(dev=%d)...\n", dev_id);
	ret = IMP_AI_Enable(dev_id);
	if (ret != 0) {
		fprintf(stderr, "[imp-test-audio] FAIL: IMP_AI_Enable returned %d (errno=%d %s)\n",
			ret, errno, strerror(errno));
		IMP_System_Exit();
		return 4;
	}
	fprintf(stderr, "[imp-test-audio] OK: IMP_AI_Enable\n");

	/* Step 4: IMP_AI_SetChnParam */
	IMPAudioIChnParam chnParam;
	memset(&chnParam, 0, sizeof(chnParam));
	chnParam.usrFrmDepth = frm_depth;
	chnParam.Rev = 0;

	fprintf(stderr, "[imp-test-audio] IMP_AI_SetChnParam(dev=%d, chn=%d, depth=%d)...\n",
		dev_id, chn_id, frm_depth);
	ret = IMP_AI_SetChnParam(dev_id, chn_id, &chnParam);
	if (ret != 0) {
		fprintf(stderr, "[imp-test-audio] FAIL: IMP_AI_SetChnParam returned %d (errno=%d %s)\n",
			ret, errno, strerror(errno));
		IMP_AI_Disable(dev_id);
		IMP_System_Exit();
		return 5;
	}
	fprintf(stderr, "[imp-test-audio] OK: IMP_AI_SetChnParam\n");

	/* Step 5: IMP_AI_EnableChn */
	fprintf(stderr, "[imp-test-audio] IMP_AI_EnableChn(dev=%d, chn=%d)...\n", dev_id, chn_id);
	ret = IMP_AI_EnableChn(dev_id, chn_id);
	if (ret != 0) {
		fprintf(stderr, "[imp-test-audio] FAIL: IMP_AI_EnableChn returned %d (errno=%d %s)\n",
			ret, errno, strerror(errno));
		IMP_AI_Disable(dev_id);
		IMP_System_Exit();
		return 6;
	}
	fprintf(stderr, "[imp-test-audio] OK: IMP_AI_EnableChn\n");

	/* Step 6: IMP_AI_SetVol */
	fprintf(stderr, "[imp-test-audio] IMP_AI_SetVol(dev=%d, chn=%d, vol=%d)...\n",
		dev_id, chn_id, volume);
	ret = IMP_AI_SetVol(dev_id, chn_id, volume);
	if (ret != 0) {
		fprintf(stderr, "[imp-test-audio] FAIL: IMP_AI_SetVol returned %d (errno=%d %s)\n",
			ret, errno, strerror(errno));
		IMP_AI_DisableChn(dev_id, chn_id);
		IMP_AI_Disable(dev_id);
		IMP_System_Exit();
		return 7;
	}
	{
		int cur_vol = 0;
		IMP_AI_GetVol(dev_id, chn_id, &cur_vol);
		fprintf(stderr, "[imp-test-audio] OK: IMP_AI_SetVol (readback vol=%d)\n", cur_vol);
	}

	/* Step 7: IMP_AI_SetGain (optional) */
	if (gain >= 0) {
		fprintf(stderr, "[imp-test-audio] IMP_AI_SetGain(dev=%d, chn=%d, gain=%d)...\n",
			dev_id, chn_id, gain);
		ret = IMP_AI_SetGain(dev_id, chn_id, gain);
		if (ret != 0) {
			fprintf(stderr, "[imp-test-audio] FAIL: IMP_AI_SetGain returned %d (errno=%d %s)\n",
				ret, errno, strerror(errno));
			IMP_AI_DisableChn(dev_id, chn_id);
			IMP_AI_Disable(dev_id);
			IMP_System_Exit();
			return 8;
		}
	}
	{
		int cur_gain = 0;
		IMP_AI_GetGain(dev_id, chn_id, &cur_gain);
		fprintf(stderr, "[imp-test-audio] gain readback=%d\n", cur_gain);
	}

	fprintf(stderr, "[imp-test-audio] --- starting capture loop (%d frames, Ctrl-C to stop) ---\n",
		max_frames);

	int frame_count = 0;
	int poll_errors = 0;
	int get_errors  = 0;
	int release_errors = 0;
	size_t total_bytes = 0;
	int exit_code = 0;

	while (!g_quit) {
		if (max_frames > 0 && frame_count >= max_frames)
			break;

		ret = IMP_AI_PollingFrame(dev_id, chn_id, (unsigned int)timeout_ms);
		if (ret != 0) {
			poll_errors++;
			fprintf(stderr, "[imp-test-audio] WARN: IMP_AI_PollingFrame timeout (%d total)\n",
				poll_errors);
			if (poll_errors >= 10) {
				fprintf(stderr, "[imp-test-audio] FAIL: too many poll timeouts, aborting\n");
				exit_code = 9;
				break;
			}
			continue;
		}

		IMPAudioFrame frame;
		memset(&frame, 0, sizeof(frame));
		ret = IMP_AI_GetFrame(dev_id, chn_id, &frame, IMP_BLOCK);
		if (ret != 0) {
			get_errors++;
			fprintf(stderr, "[imp-test-audio] ERROR: IMP_AI_GetFrame returned %d (errno=%d %s) [%d total]\n",
				ret, errno, strerror(errno), get_errors);
			if (get_errors >= 10) {
				fprintf(stderr, "[imp-test-audio] FAIL: too many GetFrame errors, aborting\n");
				exit_code = 10;
				break;
			}
			continue;
		}

		frame_count++;
		total_bytes += frame.len;

		if (frame_count <= 5 || frame_count % 25 == 0) {
			fprintf(stderr, "[imp-test-audio] frame #%d: len=%d ts=%lld seq=%d virAddr=%p\n",
				frame_count, frame.len, (long long)frame.timeStamp,
				frame.seq, (void *)frame.virAddr);
		}

		if (outfile && frame.virAddr && frame.len > 0) {
			fwrite(frame.virAddr, 1, frame.len, outfile);
		}

		ret = IMP_AI_ReleaseFrame(dev_id, chn_id, &frame);
		if (ret != 0) {
			release_errors++;
			fprintf(stderr, "[imp-test-audio] WARN: IMP_AI_ReleaseFrame returned %d [%d total]\n",
				ret, release_errors);
		}
	}

	fprintf(stderr, "\n[imp-test-audio] --- capture done ---\n");
	fprintf(stderr, "[imp-test-audio] frames=%d bytes=%zu poll_errors=%d get_errors=%d release_errors=%d\n",
		frame_count, total_bytes, poll_errors, get_errors, release_errors);

	/* Cleanup */
	fprintf(stderr, "[imp-test-audio] IMP_AI_DisableChn(dev=%d, chn=%d)...\n", dev_id, chn_id);
	ret = IMP_AI_DisableChn(dev_id, chn_id);
	fprintf(stderr, "[imp-test-audio] IMP_AI_DisableChn returned %d\n", ret);

	fprintf(stderr, "[imp-test-audio] IMP_AI_Disable(dev=%d)...\n", dev_id);
	ret = IMP_AI_Disable(dev_id);
	fprintf(stderr, "[imp-test-audio] IMP_AI_Disable returned %d\n", ret);

	fprintf(stderr, "[imp-test-audio] IMP_System_Exit...\n");
	ret = IMP_System_Exit();
	fprintf(stderr, "[imp-test-audio] IMP_System_Exit returned %d\n", ret);

	if (outfile && outfile != stdout)
		fclose(outfile);

	fprintf(stderr, "[imp-test-audio] exit code=%d\n", exit_code);
	return exit_code;
}
