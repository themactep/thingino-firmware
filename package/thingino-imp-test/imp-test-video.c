/*
 * imp-test-video - minimal IMP video bring-up harness.
 *
 * FrameSource chn0 -> encoder chn0, no OSD/RTSP/threads, so the libimp +
 * kernel-driver encoder handoff can be exercised on its own.  It logs to
 * stdout and to /tmp/imp-test-video.log, installs a SIGSEGV handler that
 * prints pc/ra/sp/gp and the faulting mapping, and keeps a canary next to
 * its locals so a caller-stack smash shows up before the crash.
 *
 * Usage: imp-test-video [poll_timeout_ms]
 *   poll_timeout_ms > 0 : IMP_Encoder_PollingStream blocks (argv default 1)
 *   poll_timeout_ms = 0 : non-blocking poll
 *
 * On the T31 open-tx-isp driver the blocking path returns with a wild
 * callee-saved register (s0) and the caller faults; timeout 0 is clean.
 * That is what package/timps/0001-t31-nonblocking-pollingstream.patch works
 * around in timps.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <ucontext.h>
#include <imp/imp_system.h>
#include <imp/imp_isp.h>
#include <imp/imp_framesource.h>
#include <imp/imp_encoder.h>

static IMPSensorInfo g_sensor;
static int L = 1;

#define P(...) do { dprintf(1, __VA_ARGS__); dprintf(L, __VA_ARGS__); } while (0)

static void on_segv(int s, siginfo_t *si, void *uc)
{
	ucontext_t *u = uc;
	unsigned long pc = (unsigned long)u->uc_mcontext.pc;
	FILE *f;
	(void)s;

	P("*** SIGSEGV pc=%08lx ra=%08lx sp=%08lx gp=%08lx si=%08lx\n",
	  pc, (unsigned long)u->uc_mcontext.gregs[31],
	  (unsigned long)u->uc_mcontext.gregs[29],
	  (unsigned long)u->uc_mcontext.gregs[28],
	  (unsigned long)(si ? si->si_addr : 0));
	f = fopen("/proc/self/maps", "r");
	if (f) {
		char line[512];
		while (fgets(line, sizeof line, f)) {
			unsigned long lo, hi;
			if (sscanf(line, "%lx-%lx", &lo, &hi) == 2 &&
			    pc >= lo && pc < hi)
				P("fault-in: %s", line);
		}
		fclose(f);
	}
	_exit(139);
}

int main(int argc, char **argv)
{
	int ret, i, timeout = (argc > 1) ? atoi(argv[1]) : 1;
	struct sigaction sa;

	L = open("/tmp/imp-test-video.log", O_WRONLY | O_CREAT | O_TRUNC, 0644);
	if (L < 0)
		L = 1;
	memset(&sa, 0, sizeof sa);
	sa.sa_sigaction = on_segv;
	sa.sa_flags = SA_SIGINFO;
	sigaction(SIGSEGV, &sa, NULL);
	sigaction(SIGBUS, &sa, NULL);

	memset(&g_sensor, 0, sizeof g_sensor);
	snprintf(g_sensor.name, sizeof g_sensor.name, "sc2336");
	g_sensor.cbus_type = TX_SENSOR_CONTROL_INTERFACE_I2C;
	snprintf(g_sensor.i2c.type, sizeof g_sensor.i2c.type, "sc2336");
	g_sensor.i2c.addr = 0x30;

	P("poll_timeout=%d\n", timeout);
	ret = IMP_ISP_Open();                P("ISP_Open=%d\n", ret);
	ret = IMP_ISP_AddSensor(&g_sensor);  P("AddSensor=%d\n", ret);
	ret = IMP_ISP_EnableSensor();        P("EnableSensor=%d\n", ret);
	for (i = 0; (ret = IMP_System_Init()) < 0 && i < 5; i++) {
		P("System_Init busy %d\n", i + 1);
		usleep(1000000);
	}
	P("System_Init=%d\n", ret);
	IMP_ISP_EnableTuning();

	IMPFSChnAttr a; memset(&a, 0, sizeof a);
	a.pixFmt = PIX_FMT_NV12;
	a.outFrmRateNum = 25; a.outFrmRateDen = 1;
	a.type = FS_PHY_CHANNEL;
	a.nrVBs = 1;
	a.crop.enable = 1; a.crop.left = 0; a.crop.top = 0;
	a.crop.width = 1920; a.crop.height = 1080;
	a.scaler.enable = 0;
	a.picWidth = 1920; a.picHeight = 1080;
	ret = IMP_FrameSource_CreateChn(0, &a);  P("FS_CreateChn=%d\n", ret);
	ret = IMP_FrameSource_SetChnAttr(0, &a); P("FS_SetChnAttr=%d\n", ret);

	ret = IMP_Encoder_CreateGroup(0);        P("Enc_CreateGroup=%d\n", ret);
	IMPEncoderChnAttr ea; memset(&ea, 0, sizeof ea);
	IMP_Encoder_SetDefaultParam(&ea, IMP_ENC_PROFILE_AVC_MAIN, IMP_ENC_RC_MODE_CBR,
	                            1920, 1080, 25, 1, 50, 1, -1, 2000);
	ret = IMP_Encoder_CreateChn(0, &ea);     P("Enc_CreateChn=%d\n", ret);
	ret = IMP_Encoder_RegisterChn(0, 0);     P("Enc_RegisterChn=%d\n", ret);

	IMPCell fs = { DEV_ID_FS, 0, 0 }, enc = { DEV_ID_ENC, 0, 0 };
	ret = IMP_System_Bind(&fs, &enc);        P("Bind=%d\n", ret);

	ret = IMP_FrameSource_EnableChn(0);      P("FS_EnableChn=%d\n", ret);
	ret = IMP_Encoder_StartRecvPic(0);       P("StartRecvPic=%d\n", ret);

	volatile unsigned canary = 0xdeadbeef;
	P("canary0=%08x\n", canary);
	for (i = 0; i < 40; i++) {
		usleep(200000);
		ret = IMP_Encoder_PollingStream(0, timeout);
		P("i=%d canary=%08x ret=%d\n", i, canary, ret);
		if (canary != 0xdeadbeef) {
			P("*** CALLER STACK SMASHED after PollingStream (i=%d) ***\n", i);
			break;
		}
	}
	P("DONE canary=%08x i=%d\n", canary, i);
	return 0;
}
