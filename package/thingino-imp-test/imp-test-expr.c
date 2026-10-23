/*
 * imp-test-expr - Manual-exposure (fixed shutter) probe for libimp
 *
 * Answers one question on whatever SoC it runs on: does this libimp
 * honor IMP_ISP_Tuning_SetExpr(MANUAL, ...) to pin the AE integration
 * time, or does AE re-seize control afterwards?
 *
 * Layers:
 *   --probe        dlopen libimp and report which AE APIs are exported.
 *                  No IMP calls, no side effects, safe on any build/SoC.
 *   (default)      IMP_System_Init, read current exposure via GetExpr.
 *   --manual-us/--manual-lines
 *                  SetExpr(MANUAL, ...), read back, then watch whether
 *                  the setting sticks across a few samples.
 *   --auto         restore AE auto mode.
 *   --cap-us/--cap-lines
 *                  IMP_ISP_Tuning_SetAe_IT_MAX cap (AE stays automatic,
 *                  integration time is bounded).
 *
 * API generations:
 *   Gen-1 (T10/T20/T21/T23/T30/T31-class libimp) exports
 *   IMP_ISP_Tuning_SetExpr/GetExpr. The exposure parameter is a 12-byte
 *   union: s_attr{mode, unit, time} for writes, g_attr{mode,
 *   integration_time, integration_time_min, integration_time_max,
 *   one_line_expr_in_us} for reads (all sizes from the vendor headers).
 *   XBurst2-generation libs (T32/T40/T41-class) export
 *   SetAeExprInfo/GetAeExprInfo instead. --probe reports which generation
 *   is present; the Set/Get paths here require Gen-1.
 *
 * ISP bring-up:
 *   With a streamer (prudynt/raptor/timps) running, the ISP is already
 *   open in the kernel; this tool only needs IMP_System_Init to reach
 *   the tuning ioctls. Without one, pass --sensor/--i2c-addr/--adapter
 *   (or --spi/--spi-bus) to bring the ISP up standalone:
 *   Open -> AddSensor -> EnableSensor -> EnableTuning.
 *   The tool only tears down what it brought up itself.
 *
 * Everything is resolved through dlsym, so this binary links with no
 * IMP dependencies and runs on any thingino image that ships libimp.
 *
 * Exit codes:
 *   0  success
 *   1  argument error
 *   2  libimp could not be loaded / required symbols missing
 *   3  IMP_System_Init failed
 *   4  ISP tuning unavailable (pass --sensor args, or start the streamer)
 *   5  GetExpr/SetExpr call failed
 */

#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define TAG "[expr] "

/* ------------------------------------------------------------------ */
/* Vendor ABI mirror (Gen-1 imp_isp.h). Layouts verified against the   */
/* T31/1.1.4 vendor headers; enums are plain int in this ABI.          */
/* ------------------------------------------------------------------ */

enum { XPR_MODE_AUTO = 0, XPR_MODE_MANUAL = 1 };
enum { XPR_UNIT_LINE = 0, XPR_UNIT_US = 1 };

/* 4 + 4 + 2 (+2 pad) = 12 bytes */
typedef union {
	struct {
		int mode;		/* isp_core_expr_mode */
		int unit;		/* isp_core_expr_unit */
		uint16_t time;		/* exposure value in unit */
	} s_attr;
	struct {
		int mode;
		uint16_t integration_time;	/* lines */
		uint16_t integration_time_min;
		uint16_t integration_time_max;
		uint16_t one_line_expr_in_us;
	} g_attr;
} xpr_expr_t;

enum { SENSOR_IF_I2C = 1, SENSOR_IF_SPI = 2 };

typedef struct {
	char name[32];
	int cbus_type;
	union {
		struct {
			char type[20];
			int addr;
			int i2c_adapter_id;
		} i2c;
		struct {
			char modalias[32];
			int bus_num;
		} spi;
	};
	uint16_t rst_gpio;
	uint16_t pwdn_gpio;
	uint16_t power_gpio;
} xpr_sensor_t;

/* ------------------------------------------------------------------ */
/* libimp entry points (resolved via dlsym)                            */
/* ------------------------------------------------------------------ */

typedef int (*fn_void)(void);
typedef int (*fn_expr)(xpr_expr_t *);
typedef int (*fn_sensorp)(xpr_sensor_t *);
typedef int (*fn_itmax)(unsigned int);

static void *h_imp;
static fn_void p_sys_init, p_sys_exit;
static fn_void p_isp_open, p_isp_close;
static fn_void p_enable_tuning, p_disable_tuning;
static fn_void p_enable_sensor, p_disable_sensor;
static fn_sensorp p_add_sensor, p_del_sensor;
static fn_expr p_set_expr, p_get_expr;
static fn_itmax p_set_it_max;

static const char *probe_syms[] = {
	"IMP_ISP_Tuning_SetExpr",
	"IMP_ISP_Tuning_GetExpr",
	"IMP_ISP_Tuning_SetAe_IT_MAX",
	"IMP_ISP_Tuning_GetAe_IT_MAX",
	"IMP_ISP_Tuning_SetIntegrationTime",
	"IMP_ISP_Tuning_GetIntegrationTime",
	"IMP_ISP_Tuning_SetAeAttr",
	"IMP_ISP_Tuning_GetAeAttr",
	"IMP_ISP_Tuning_SetAeExprInfo",
	"IMP_ISP_Tuning_GetAeExprInfo",
	"IMP_System_Init",
	"IMP_System_Exit",
	"IMP_ISP_Open",
	"IMP_ISP_Close",
	"IMP_ISP_AddSensor",
	"IMP_ISP_DelSensor",
	"IMP_ISP_EnableSensor",
	"IMP_ISP_DisableSensor",
	"IMP_ISP_EnableTuning",
	"IMP_ISP_DisableTuning",
};

static const char *mode_str(int mode)
{
	return mode == XPR_MODE_MANUAL ? "MANUAL" : "AUTO";
}

static void *need_sym(const char *name)
{
	void *p = dlsym(h_imp, name);
	if (!p)
		fprintf(stderr, TAG "missing symbol: %s\n", name);
	return p;
}

static void usage(int code)
{
	FILE *f = code ? stderr : stdout;
	fprintf(f,
"Usage: imp-test-expr [options]\n"
"\n"
"Actions (pick one):\n"
"  (default)            report current AE exposure state via GetExpr\n"
"  --probe              list which AE APIs this libimp exports, then exit\n"
"  --manual-us N        pin exposure at N microseconds (SetExpr MANUAL)\n"
"  --manual-lines N     pin exposure at N sensor lines (SetExpr MANUAL)\n"
"  --auto               restore AE auto exposure\n"
"  --cap-us N           cap AE integration at N us (SetAe_IT_MAX)\n"
"  --cap-lines N        cap AE integration at N lines (SetAe_IT_MAX)\n"
"\n"
"Options:\n"
"  --watch N            after the action, sample GetExpr N seconds (1 Hz)\n"
"                       and report whether MANUAL stuck\n"
"  --sensor NAME        sensor driver name for standalone ISP bring-up\n"
"  --i2c-addr ADDR      sensor i2c address (hex, e.g. 0x30)\n"
"  --adapter N          i2c adapter id (default 0)\n"
"  --spi NAME           SPI sensor modalias (instead of --sensor)\n"
"  --spi-bus N          SPI bus number (default 0)\n"
"\n"
"A streamer running on the camera satisfies the ISP bring-up on its own;\n"
"--sensor/--spi args are only needed when no streamer is running.\n");
	exit(code);
}

static void die(int code, const char *msg)
{
	fprintf(stderr, TAG "%s\n", msg);
	if (p_sys_exit)
		p_sys_exit();
	exit(code);
}

/* Try EnableTuning; if it fails, a successful GetExpr readback still
 * means tuning ioctls are reachable (ISP already up, e.g. streamer). */
static int tuning_ready(void)
{
	xpr_expr_t e;

	if (!p_get_expr)
		return 0;
	memset(&e, 0, sizeof(e));
	return p_get_expr(&e) == 0;
}

static int isp_bring_up(const char *sensor, long i2c_addr, long adapter,
			const char *spi, long spi_bus)
{
	xpr_sensor_t info;
	int ret;

	if (p_isp_open) {
		ret = p_isp_open();
		if (ret != 0) {
			fprintf(stderr, TAG "IMP_ISP_Open failed: %d\n", ret);
			return 0;
		}
	}

	memset(&info, 0, sizeof(info));
	if (spi) {
		info.cbus_type = SENSOR_IF_SPI;
		strncpy(info.spi.modalias, spi, sizeof(info.spi.modalias) - 1);
		info.spi.bus_num = (int)spi_bus;
	} else {
		info.cbus_type = SENSOR_IF_I2C;
		strncpy(info.i2c.type, sensor, sizeof(info.i2c.type) - 1);
		info.i2c.addr = (int)i2c_addr;
		info.i2c.i2c_adapter_id = (int)adapter;
	}

	if ((ret = p_add_sensor(&info)) != 0) {
		fprintf(stderr, TAG "IMP_ISP_AddSensor failed: %d\n", ret);
		return 0;
	}
	if ((ret = p_enable_sensor()) != 0) {
		fprintf(stderr, TAG "IMP_ISP_EnableSensor failed: %d\n", ret);
		return 0;
	}
	if ((ret = p_enable_tuning()) != 0) {
		fprintf(stderr, TAG "IMP_ISP_EnableTuning failed: %d\n", ret);
		return 0;
	}
	return 1;
}

static void isp_tear_down(void)
{
	if (p_disable_tuning)
		p_disable_tuning();
	if (p_disable_sensor)
		p_disable_sensor();
	if (p_del_sensor) {
		xpr_sensor_t info;
		memset(&info, 0, sizeof(info));
		p_del_sensor(&info);
	}
	if (p_isp_close)
		p_isp_close();
}

static int get_expr(xpr_expr_t *e)
{
	int ret;

	memset(e, 0, sizeof(*e));
	ret = p_get_expr(e);
	if (ret != 0)
		fprintf(stderr, TAG "IMP_ISP_Tuning_GetExpr failed: %d\n", ret);
	return ret;
}

static void print_expr(const xpr_expr_t *e, const char *prefix)
{
	printf(TAG "%smode=%s integration_time=%u lines "
	       "(min=%u max=%u) line_us=%u\n",
	       prefix ? prefix : "",
	       mode_str(e->g_attr.mode),
	       e->g_attr.integration_time,
	       e->g_attr.integration_time_min,
	       e->g_attr.integration_time_max,
	       e->g_attr.one_line_expr_in_us);
}

static void watch(int seconds, int expect_manual)
{
	int i, manual_hits = 0;
	xpr_expr_t e;

	for (i = 0; i < seconds; i++) {
		sleep(1);
		if (get_expr(&e) != 0)
			return;
		printf(TAG "watch %d/%d: mode=%s integration_time=%u\n",
		       i + 1, seconds, mode_str(e.g_attr.mode),
		       e.g_attr.integration_time);
		if (e.g_attr.mode == XPR_MODE_MANUAL)
			manual_hits++;
	}

	if (!expect_manual)
		return;

	if (manual_hits == seconds)
		printf(TAG "VERDICT: MANUAL HONORED (%d/%d samples)\n",
		       manual_hits, seconds);
	else if (manual_hits > 0)
		printf(TAG "VERDICT: PARTIAL - AE re-seized control "
		       "(%d/%d samples MANUAL)\n", manual_hits, seconds);
	else
		printf(TAG "VERDICT: NOT HONORED - AE re-seized control "
		       "immediately\n");
}

int main(int argc, char **argv)
{
	enum {
		A_REPORT, A_PROBE, A_MANUAL, A_AUTO, A_CAP,
	} action = A_REPORT;
	int unit = XPR_UNIT_US;
	long value = 0, watch_secs = 0;
	long i2c_addr = -1, adapter = 0, spi_bus = 0;
	const char *sensor = NULL, *spi = NULL;
	int i, ret, brought_up = 0;
	xpr_expr_t e;
	unsigned int lines;
	static const char *so_names[] = { "libimp.so", "/usr/lib/libimp.so" };
	const char *so_loaded = NULL;

	for (i = 1; i < argc; i++) {
		if (!strcmp(argv[i], "--probe"))
			action = A_PROBE;
		else if (!strcmp(argv[i], "--manual-us")) {
			action = A_MANUAL;
			unit = XPR_UNIT_US;
			value = (++i < argc) ? atol(argv[i]) : -1;
		} else if (!strcmp(argv[i], "--manual-lines")) {
			action = A_MANUAL;
			unit = XPR_UNIT_LINE;
			value = (++i < argc) ? atol(argv[i]) : -1;
		} else if (!strcmp(argv[i], "--auto")) {
			action = A_AUTO;
		} else if (!strcmp(argv[i], "--cap-us")) {
			action = A_CAP;
			unit = XPR_UNIT_US;
			value = (++i < argc) ? atol(argv[i]) : -1;
		} else if (!strcmp(argv[i], "--cap-lines")) {
			action = A_CAP;
			unit = XPR_UNIT_LINE;
			value = (++i < argc) ? atol(argv[i]) : -1;
		} else if (!strcmp(argv[i], "--watch")) {
			watch_secs = (++i < argc) ? atol(argv[i]) : 0;
		} else if (!strcmp(argv[i], "--sensor")) {
			sensor = (++i < argc) ? argv[i] : NULL;
		} else if (!strcmp(argv[i], "--i2c-addr")) {
			i2c_addr = (++i < argc) ? strtol(argv[i], NULL, 0) : -1;
		} else if (!strcmp(argv[i], "--adapter")) {
			adapter = (++i < argc) ? atol(argv[i]) : 0;
		} else if (!strcmp(argv[i], "--spi")) {
			spi = (++i < argc) ? argv[i] : NULL;
		} else if (!strcmp(argv[i], "--spi-bus")) {
			spi_bus = (++i < argc) ? atol(argv[i]) : 0;
		} else if (!strcmp(argv[i], "-h") ||
			   !strcmp(argv[i], "--help")) {
			usage(0);
		} else {
			fprintf(stderr, TAG "unknown option: %s\n", argv[i]);
			usage(1);
		}
	}

	if ((action == A_MANUAL || action == A_CAP) && value <= 0) {
		fprintf(stderr, TAG "action needs a value > 0\n");
		usage(1);
	}
	if ((sensor && spi) || (sensor && i2c_addr < 0)) {
		fprintf(stderr, TAG "--sensor needs --i2c-addr, and is "
				    "mutually exclusive with --spi\n");
		usage(1);
	}

	/* ---- load libimp ---- */
	for (i = 0; i < 2 && !h_imp; i++) {
		h_imp = dlopen(so_names[i], RTLD_LAZY | RTLD_GLOBAL);
		if (h_imp)
			so_loaded = so_names[i];
	}
	if (!h_imp) {
		fprintf(stderr, TAG "cannot load libimp: %s\n", dlerror());
		return 2;
	}
	printf(TAG "libimp: %s\n", so_loaded);

	/* ---- symbol inventory ---- */
	printf(TAG "exported AE/system symbols:\n");
	for (i = 0; i < (int)(sizeof(probe_syms) / sizeof(probe_syms[0])); i++)
		printf(TAG "  %-40s %s\n", probe_syms[i],
		       dlsym(h_imp, probe_syms[i]) ? "yes" : "no");

	if (action == A_PROBE)
		return 0;

	/* ---- resolve what report/set/cap need ---- */
	p_sys_init = (fn_void)need_sym("IMP_System_Init");
	p_sys_exit = (fn_void)need_sym("IMP_System_Exit");
	p_enable_tuning = (fn_void)need_sym("IMP_ISP_EnableTuning");
	p_get_expr = (fn_expr)need_sym("IMP_ISP_Tuning_GetExpr");
	if (!p_sys_init || !p_sys_exit || !p_enable_tuning || !p_get_expr)
		return 2;

	p_isp_open = (fn_void)dlsym(h_imp, "IMP_ISP_Open");
	p_isp_close = (fn_void)dlsym(h_imp, "IMP_ISP_Close");
	p_enable_sensor = (fn_void)dlsym(h_imp, "IMP_ISP_EnableSensor");
	p_disable_tuning = (fn_void)dlsym(h_imp, "IMP_ISP_DisableTuning");
	p_disable_sensor = (fn_void)dlsym(h_imp, "IMP_ISP_DisableSensor");
	p_add_sensor = (fn_sensorp)dlsym(h_imp, "IMP_ISP_AddSensor");
	p_del_sensor = (fn_sensorp)dlsym(h_imp, "IMP_ISP_DelSensor");
	p_set_expr = (fn_expr)dlsym(h_imp, "IMP_ISP_Tuning_SetExpr");
	p_set_it_max = (fn_itmax)dlsym(h_imp, "IMP_ISP_Tuning_SetAe_IT_MAX");

	if ((action == A_MANUAL || action == A_AUTO) && !p_set_expr) {
		fprintf(stderr, TAG "SetExpr not exported by this libimp "
				    "(XBurst2 generation? see SetAeExprInfo "
				    "in the probe listing)\n");
		return 2;
	}
	if (action == A_CAP && !p_set_it_max) {
		fprintf(stderr, TAG "SetAe_IT_MAX not exported by this "
				    "libimp\n");
		return 2;
	}

	/* ---- init + tuning ---- */
	if ((ret = p_sys_init()) != 0) {
		fprintf(stderr, TAG "IMP_System_Init failed: %d\n", ret);
		return 3;
	}

	ret = p_enable_tuning();
	if (ret != 0 && tuning_ready()) {
		fprintf(stderr, TAG "EnableTuning ret=%d but tuning is "
				    "reachable; ISP already up\n", ret);
	} else if (ret != 0) {
		if (!sensor && !spi)
			die(4, "ISP tuning unavailable; start the streamer "
			       "first or pass --sensor/--spi args for "
			       "standalone bring-up");
		if (!isp_bring_up(sensor, i2c_addr, adapter, spi, spi_bus))
			die(4, "standalone ISP bring-up failed");
		brought_up = 1;
		printf(TAG "standalone ISP bring-up ok\n");
	}

	/* ---- actions ---- */
	switch (action) {
	case A_REPORT:
		if (get_expr(&e) != 0)
			die(5, "readback failed");
		print_expr(&e, "");
		break;

	case A_MANUAL:
		if (unit == XPR_UNIT_US) {
			if (get_expr(&e) != 0)
				die(5, "readback failed");
			if (e.g_attr.one_line_expr_in_us == 0)
				die(5, "line_us readback is 0; cannot "
				       "convert; use --manual-lines");
			lines = (unsigned int)((value +
				e.g_attr.one_line_expr_in_us / 2) /
				e.g_attr.one_line_expr_in_us);
			printf(TAG "manual request: %ld us = %u lines "
			       "(line_us=%u)\n", value, lines,
			       e.g_attr.one_line_expr_in_us);
			unit = XPR_UNIT_LINE;
		} else {
			lines = (unsigned int)value;
			printf(TAG "manual request: %u lines\n", lines);
		}

		memset(&e, 0, sizeof(e));
		e.s_attr.mode = XPR_MODE_MANUAL;
		e.s_attr.unit = unit;
		e.s_attr.time = (uint16_t)lines;
		ret = p_set_expr(&e);
		if (ret != 0) {
			fprintf(stderr, TAG "SetExpr(MANUAL) failed: %d\n",
				ret);
			die(5, "SetExpr rejected");
		}

		if (get_expr(&e) != 0)
			die(5, "readback failed");
		print_expr(&e, "after set: ");
		printf(TAG "%s\n",
		       e.g_attr.mode == XPR_MODE_MANUAL
		       ? "SetExpr accepted (readback MANUAL)"
		       : "readback still AUTO - not accepted");
		watch(watch_secs > 0 ? (int)watch_secs : 3, 1);
		break;

	case A_AUTO:
		memset(&e, 0, sizeof(e));
		e.s_attr.mode = XPR_MODE_AUTO;
		ret = p_set_expr(&e);
		if (ret != 0) {
			fprintf(stderr, TAG "SetExpr(AUTO) failed: %d\n", ret);
			die(5, "SetExpr rejected");
		}
		if (get_expr(&e) != 0)
			die(5, "readback failed");
		print_expr(&e, "after auto: ");
		if (watch_secs > 0)
			watch((int)watch_secs, 0);
		break;

	case A_CAP:
		if (unit == XPR_UNIT_US) {
			if (get_expr(&e) != 0)
				die(5, "readback failed");
			if (e.g_attr.one_line_expr_in_us == 0)
				die(5, "line_us readback is 0; cannot "
				       "convert; use --cap-lines");
			lines = (unsigned int)((value +
				e.g_attr.one_line_expr_in_us / 2) /
				e.g_attr.one_line_expr_in_us);
			printf(TAG "cap request: %ld us = %u lines\n",
			       value, lines);
		} else {
			lines = (unsigned int)value;
			printf(TAG "cap request: %u lines\n", lines);
		}
		ret = p_set_it_max(lines);
		if (ret != 0) {
			fprintf(stderr, TAG "SetAe_IT_MAX failed: %d\n", ret);
			die(5, "SetAe_IT_MAX rejected");
		}
		if (get_expr(&e) != 0)
			die(5, "readback failed");
		print_expr(&e, "after cap: ");
		if (watch_secs > 0)
			watch((int)watch_secs, 0);
		break;

	default:
		break;
	}

	if (brought_up)
		isp_tear_down();
	if (p_sys_exit)
		p_sys_exit();
	return 0;
}
