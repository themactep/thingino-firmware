// SPDX-License-Identifier: GPL-2.0
//
// floodlightd - Wyze Floodlight v2 (T41 / CH554 MCU) userspace daemon for thingino
//
// The floodlight white LEDs, the 3-zone PIR array and the siren are managed by
// an external CH554 MCU on /dev/ttyS2. This daemon speaks the stock serial
// protocol (reverse-engineered from Wyze iCamera - see
// docs/wyze-floodlightv2-mcu-protocol.md), reports PIR motion to thingino, and
// drives the floodlight brightness.
//
// Wire protocol (115200 8N1 raw):
//   SoC -> MCU : AA 55 43 LEN OP [DATA..] SUMhi SUMlo   (LEN = 1+ndata+2)
//   MCU -> SoC : 55 AA 43 LEN OP [DATA..] SUMhi SUMlo   (total = LEN+4)
//   SUM = 16-bit sum of every byte before the 2-byte checksum, big-endian.
//
// Commands (id / req op / resp op):
//   get brightness      0x2710  0x44 0x45
//   set brightness      0x2711  0x46 0x47   data = target, mode, ramp*100ms
//   get software        0x2712  0x3C 0x3D
//   stop brightness     0x2713  0x52 0x53
//   get pir value       0x2714  0xBC 0xBD

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <termios.h>
#include <signal.h>
#include <syslog.h>
#include <time.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>

/* ---- protocol constants ---- */
#define TX_PRE0 0xAA
#define TX_PRE1 0x55
#define TX_CLASS 0x43
#define RX_PRE0 0x55
#define RX_PRE1 0xAA

#define OP_GET_BRIGHTNESS 0x44
#define OP_SET_BRIGHTNESS 0x46
#define OP_GET_SOFTWARE   0x3C
#define OP_STOP_BRIGHT    0x52
#define OP_GET_PIR        0xBC
/* MCU->SoC opcodes are req+1 (0x45,0x47,0x3D,0x53,0xBD). Async motion is also
 * reported as a 0xBD PIR frame; confirm the exact async op on live hardware. */
#define OP_BRIGHTNESS_REPORT 0x45
#define OP_PIR_REPORT     0xBD

#define FRAME_MAX 256
#define CONTROL_SOCKET "/run/floodlightd.sock"
#define CONTROL_MAX 1024
#define CONTROL_CLIENTS 8
#define PIR_ZONES 3
#define PIR_BASELINE_SAMPLES 20
#define PIR_RISE_MIN 17

enum light_mode {
	LIGHT_AUTO,
	LIGHT_MANUAL_ON,
	LIGHT_MANUAL_OFF,
};

enum active_policy {
	ACTIVE_ALWAYS,
	ACTIVE_NIGHT,
	ACTIVE_CLOCK,
};

struct control_client {
	int fd;
	int monitor;
	int len;
	char buf[CONTROL_MAX];
};

struct pir_filter {
	uint16_t baseline[PIR_BASELINE_SAMPLES];
	uint32_t baseline_sum;
	unsigned int baseline_pos;
	uint16_t previous;
	uint16_t previous2;
	unsigned int rising_samples;
	int have_previous;
};

/* ---- config (overridable via CLI) ---- */
static const char *g_tty   = "/dev/ttyS2";
static speed_t     g_baud  = B115200;
static int         g_bright_on   = 100;   /* brightness when motion fires   */
static int         g_bright_mode = 0;     /* set-brightness mode byte        */
static int         g_ramp_100ms  = 5;     /* ramp duration, units of 100 ms  */
static int         g_motion_hold = 30;    /* seconds to hold flood after motion */
static int         g_poll_ms     = 500;   /* PIR poll cadence (0 = passive)   */
static int         g_pir_sensitivity = 255; /* stock default, range 0..255     */
static int         g_pir_zone_mask = 7;  /* bit 0=left, 1=middle, 2=right     */
static enum active_policy g_active_policy = ACTIVE_ALWAYS;
static int         g_active_start = 18 * 60; /* minutes after local midnight */
static int         g_active_end   = 6 * 60;
static const char *g_daynight_file = "/run/thingino/daynight_mode";
static const char *g_hook  = "/etc/floodlightd/motion.sh"; /* run on motion   */
static const char *g_control_path = CONTROL_SOCKET;
static int         g_foreground = 0;
static int         g_verbose    = 0;

static volatile sig_atomic_t g_run = 1;
static int g_fd = -1;
static int g_control_fd = -1;
static struct control_client g_clients[CONTROL_CLIENTS];
static time_t g_last_motion = 0;
static time_t g_override_until = 0;
static enum light_mode g_light_mode = LIGHT_AUTO;
static int g_light_level = 0;
static uint16_t g_pir_raw[PIR_ZONES];
static int g_pir_trigger[PIR_ZONES];
static time_t g_pir_motion_time[PIR_ZONES];
static struct pir_filter g_pir_filter[PIR_ZONES];
static unsigned long g_pir_frames;
static unsigned long g_pir_nonzero_frames;
static unsigned long g_pir_motion_events;
static unsigned long g_pir_suppressed_events;
static int g_zero_pir_warned;
static int g_active_now = -1;

static void on_sig(int s) { (void)s; g_run = 0; }

static void logv(int pri, const char *fmt, ...)
{
	va_list ap; va_start(ap, fmt);
	if (g_foreground) { vfprintf(stderr, fmt, ap); fputc('\n', stderr); }
	else vsyslog(pri, fmt, ap);
	va_end(ap);
}

static const char *light_mode_name(void)
{
	switch (g_light_mode) {
	case LIGHT_MANUAL_ON: return "manual_on";
	case LIGHT_MANUAL_OFF: return "manual_off";
	default: return "auto";
	}
}

static long override_remaining(void)
{
	if (!g_override_until) return 0;
	long remaining = (long)(g_override_until - time(NULL));
	return remaining > 0 ? remaining : 0;
}

static int pir_threshold(void)
{
	if (g_pir_sensitivity < 103) return 140;
	if (g_pir_sensitivity < 154) return 120;
	return 22;
}

static const char *active_policy_name(void)
{
	switch (g_active_policy) {
	case ACTIVE_NIGHT: return "night";
	case ACTIVE_CLOCK: return "clock";
	default: return "always";
	}
}

static int parse_clock(const char *text, int *minutes)
{
	char *end;
	long hour, minute;

	if (!text || strlen(text) != 5 || text[2] != ':') return -1;
	errno = 0;
	hour = strtol(text, &end, 10);
	if (errno || end != text + 2) return -1;
	errno = 0;
	minute = strtol(text + 3, &end, 10);
	if (errno || *end || hour < 0 || hour > 23 || minute < 0 || minute > 59)
		return -1;
	*minutes = (int)(hour * 60 + minute);
	return 0;
}

static int parse_active_window(const char *text, int *start, int *end)
{
	char from[6], to[6];

	if (!text || strlen(text) != 11 || text[5] != '-') return -1;
	memcpy(from, text, 5);
	from[5] = '\0';
	memcpy(to, text + 6, 5);
	to[5] = '\0';
	return parse_clock(from, start) == 0 && parse_clock(to, end) == 0 ? 0 : -1;
}

static int set_active_policy(const char *text)
{
	if (!strcmp(text, "always")) g_active_policy = ACTIVE_ALWAYS;
	else if (!strcmp(text, "night")) g_active_policy = ACTIVE_NIGHT;
	else if (!strcmp(text, "clock")) g_active_policy = ACTIVE_CLOCK;
	else return -1;
	return 0;
}

static void format_active_window(char *buf, size_t size)
{
	unsigned int start = (unsigned int)g_active_start % (24 * 60);
	unsigned int end = (unsigned int)g_active_end % (24 * 60);

	snprintf(buf, size, "%02u:%02u-%02u:%02u",
		start / 60, start % 60, end / 60, end % 60);
}

static int read_daynight_state(char *state, size_t size)
{
	FILE *fp;
	char value[16];

	if (size) snprintf(state, size, "unknown");
	fp = fopen(g_daynight_file, "r");
	if (!fp) return -1;
	if (fscanf(fp, "%15s", value) != 1) {
		fclose(fp);
		return -1;
	}
	fclose(fp);
	if (strcmp(value, "day") && strcmp(value, "night")) return -1;
	if (size) snprintf(state, size, "%s", value);
	return !strcmp(value, "night");
}

static int active_policy_now(char *daynight_state, size_t state_size)
{
	time_t now;
	struct tm local;
	int minute;

	if (daynight_state && state_size)
		snprintf(daynight_state, state_size, "n/a");
	if (g_active_policy == ACTIVE_ALWAYS) return 1;
	if (g_active_policy == ACTIVE_NIGHT)
		return read_daynight_state(daynight_state, state_size) == 1;

	now = time(NULL);
	if (!localtime_r(&now, &local)) return 0;
	minute = local.tm_hour * 60 + local.tm_min;
	if (g_active_start == g_active_end) return 1;
	if (g_active_start < g_active_end)
		return minute >= g_active_start && minute < g_active_end;
	return minute >= g_active_start || minute < g_active_end;
}

static int pir_motion_latched(int zone, time_t now)
{
	if (!g_pir_motion_time[zone]) return 0;
	if (g_motion_hold <= 0) return 1;
	return now < g_pir_motion_time[zone] ||
	       now - g_pir_motion_time[zone] < g_motion_hold;
}

static int state_json(char *buf, size_t size, const char *event)
{
	time_t now = time(NULL);
	char window[16], daynight_state[16];
	int motion[PIR_ZONES];
	int active_now = active_policy_now(daynight_state, sizeof daynight_state);
	long last_motion_ago = g_last_motion ? (long)(now - g_last_motion) : -1;

	if (last_motion_ago < 0 && g_last_motion) last_motion_ago = 0;
	for (int i = 0; i < PIR_ZONES; i++)
		motion[i] = pir_motion_latched(i, now);
	format_active_window(window, sizeof window);
	return snprintf(buf, size,
		"{\"event\":\"%s\",\"mode\":\"%s\",\"light\":%s,"
		"\"level\":%d,\"auto_brightness\":%d,\"hold\":%d,"
		"\"override_remaining\":%ld,\"pir_raw\":[%u,%u,%u],"
		"\"pir_trigger\":[%d,%d,%d],\"pir_motion\":[%d,%d,%d],"
		"\"pir_frames\":%lu,"
		"\"pir_nonzero_frames\":%lu,\"pir_sensitivity\":%d,"
		"\"pir_threshold\":%d,\"pir_zone_mask\":%d,"
		"\"motion_events\":%lu,\"suppressed_events\":%lu,"
		"\"last_motion_ago\":%ld,\"active_policy\":\"%s\","
		"\"active_now\":%s,\"active_window\":\"%s\","
		"\"daynight_state\":\"%s\"}\n",
		event, light_mode_name(), g_light_level > 0 ? "true" : "false",
		g_light_level, g_bright_on, g_motion_hold, override_remaining(),
		g_pir_raw[0], g_pir_raw[1], g_pir_raw[2],
		g_pir_trigger[0], g_pir_trigger[1], g_pir_trigger[2],
		motion[0], motion[1], motion[2],
		g_pir_frames, g_pir_nonzero_frames, g_pir_sensitivity,
		pir_threshold(), g_pir_zone_mask, g_pir_motion_events,
		g_pir_suppressed_events, last_motion_ago, active_policy_name(),
		active_now ? "true" : "false", window, daynight_state);
}

static int control_write(int fd, const char *buf, size_t len)
{
	while (len) {
		ssize_t written = send(fd, buf, len, MSG_NOSIGNAL);
		if (written < 0) {
			if (errno == EINTR) continue;
			return -1;
		}
		if (written == 0) return -1;
		buf += written;
		len -= written;
	}
	return 0;
}

static void control_close_client(int slot)
{
	if (g_clients[slot].fd >= 0) close(g_clients[slot].fd);
	g_clients[slot].fd = -1;
	g_clients[slot].monitor = 0;
	g_clients[slot].len = 0;
}

static void monitor_emit(const char *fmt, ...)
{
	char line[CONTROL_MAX];
	va_list ap;
	va_start(ap, fmt);
	int len = vsnprintf(line, sizeof line - 2, fmt, ap);
	va_end(ap);
	if (len < 0) return;
	if (len > (int)sizeof line - 2) len = sizeof line - 2;
	line[len++] = '\n';
	line[len] = '\0';

	for (int i = 0; i < CONTROL_CLIENTS; i++) {
		if (g_clients[i].fd >= 0 && g_clients[i].monitor &&
		    control_write(g_clients[i].fd, line, len) != 0)
			control_close_client(i);
	}
}

static void control_send_state(int fd, const char *event)
{
	char line[CONTROL_MAX];
	int len = state_json(line, sizeof line, event);
	if (len > 0) control_write(fd, line, len);
}

/* ---- serial ---- */
static int tty_open(const char *dev, speed_t baud)
{
	int fd = open(dev, O_RDWR | O_NOCTTY | O_NONBLOCK);
	if (fd < 0) return -1;
	/* Match stock ttys2_open(): open nonblocking, then immediately clear the
	 * file status flags before configuring the line.  Leaving O_NONBLOCK set
	 * can drop commands with EAGAIN when the MCU is being polled. */
	if (fcntl(fd, F_SETFL, 0) != 0) { close(fd); return -1; }

	struct termios t;
	if (tcgetattr(fd, &t) != 0) { close(fd); return -1; }
	cfmakeraw(&t);
	t.c_cflag &= ~(CSIZE | CSTOPB | PARENB | CRTSCTS);
	t.c_cflag |= (CS8 | CLOCAL | CREAD);
	t.c_cc[VMIN]  = 1;
	t.c_cc[VTIME] = 0;
	cfsetispeed(&t, baud);
	cfsetospeed(&t, baud);
	tcflush(fd, TCIFLUSH);
	if (tcsetattr(fd, TCSAFLUSH, &t) != 0) { close(fd); return -1; }
	return fd;
}

/* 16-bit additive checksum over n bytes, big-endian trailer */
static uint16_t cksum(const uint8_t *b, int n)
{
	uint32_t s = 0;
	for (int i = 0; i < n; i++) s += b[i];
	return (uint16_t)(s & 0xffff);
}

/* Build & send a SoC->MCU command. data may be NULL. Returns 0 on success. */
static int mcu_send(uint8_t op, const uint8_t *data, int ndata)
{
	uint8_t f[FRAME_MAX];
	int i = 0;
	f[i++] = TX_PRE0;
	f[i++] = TX_PRE1;
	f[i++] = TX_CLASS;
	f[i++] = (uint8_t)(1 + ndata + 2);   /* LEN = op + data + checksum */
	f[i++] = op;
	for (int k = 0; k < ndata; k++) f[i++] = data[k];
	uint16_t c = cksum(f, i);
	f[i++] = (uint8_t)(c >> 8);
	f[i++] = (uint8_t)(c & 0xff);

	int off = 0;
	while (off < i) {
		int w = write(g_fd, f + off, i - off);
		if (w < 0) {
			if (errno == EINTR) continue;
			logv(LOG_ERR, "ttyS2 write: %s", strerror(errno));
			return -1;
		}
		off += w;
	}
	if (g_verbose) {
		char hex[FRAME_MAX * 3]; int p = 0;
		for (int k = 0; k < i; k++) p += sprintf(hex + p, "%02x ", f[k]);
		logv(LOG_DEBUG, "TX op=0x%02x: %s", op, hex);
	}
	return 0;
}

/* ---- motion actions ---- */
static void run_hook(const char *zones)
{
	if (!g_hook || !*g_hook) return;
	if (access(g_hook, X_OK) != 0) return;
	pid_t pid = fork();
	if (pid == 0) {
		execl(g_hook, g_hook, zones, (char *)NULL);
		_exit(127);
	} else if (pid > 0) {
		/* reaped by SIGCHLD default / waitpid in loop */
	}
}

static int floodlight_set(int level, const char *source)
{
	if (level < 0) level = 0;
	if (level > 100) level = 100;
	uint8_t d[3] = { (uint8_t)level, (uint8_t)g_bright_mode, (uint8_t)g_ramp_100ms };
	if (mcu_send(OP_SET_BRIGHTNESS, d, 3) != 0) return -1;
	int changed = level != g_light_level;
	g_light_level = level;
	if (changed)
		monitor_emit("{\"event\":\"light\",\"on\":%s,\"level\":%d,\"source\":\"%s\"}",
			level > 0 ? "true" : "false", level, source);
	return 0;
}

static void refresh_active_state(const char *source)
{
	char daynight_state[16];
	int active = active_policy_now(daynight_state, sizeof daynight_state);

	if (active == g_active_now) {
		if (!active && g_light_mode == LIGHT_AUTO && g_light_level > 0)
			floodlight_set(0, "inactive_window");
		return;
	}
	g_active_now = active;
	logv(LOG_INFO, "automatic PIR actions %s (policy=%s, daynight=%s)",
		active ? "enabled" : "disabled", active_policy_name(), daynight_state);
	monitor_emit("{\"event\":\"active\",\"active\":%s,\"policy\":\"%s\","
		"\"daynight_state\":\"%s\",\"source\":\"%s\"}",
		active ? "true" : "false", active_policy_name(), daynight_state, source);
	if (!active && g_light_mode == LIGHT_AUTO && g_light_level > 0)
		floodlight_set(0, "inactive_window");
}

static void resume_auto(const char *source)
{
	g_light_mode = LIGHT_AUTO;
	g_override_until = 0;
	if (active_policy_now(NULL, 0) && g_last_motion && (g_motion_hold <= 0 ||
	    time(NULL) - g_last_motion < g_motion_hold)) {
		floodlight_set(g_bright_on, source);
	} else {
		floodlight_set(0, source);
	}
	monitor_emit("{\"event\":\"mode\",\"mode\":\"auto\",\"source\":\"%s\"}", source);
}

/* Wyze's fixed 4.53.2 PIR path does not send an initialization command to the
 * CH554.  It filters the three raw 16-bit samples in iCamera: a 20-sample
 * running baseline, a sensitivity-dependent delta (140/120/22), and a rising
 * edge of at least 17 counts.  It also rejects values outside the useful PIR
 * range.  This is a compact equivalent of that stateful host-side filter. */
static int pir_filter_sample(int zone, uint16_t raw)
{
	struct pir_filter *filter = &g_pir_filter[zone];
	int threshold = pir_threshold();
	int rising = 0;

	if (!(g_pir_zone_mask & (1 << zone))) return 0;
	if (raw > 2000 || raw >= threshold + 75) return 0;
	if (filter->have_previous && raw == filter->previous) return 0;

	if (!filter->have_previous || raw < filter->previous) {
		filter->rising_samples = 0;
	} else {
		filter->rising_samples++;
		if (filter->rising_samples >= 2 &&
		    ((unsigned int)(raw - filter->previous) >= PIR_RISE_MIN ||
		     (unsigned int)(raw - filter->previous2) >= PIR_RISE_MIN))
			rising = 1;
	}

	filter->previous2 = filter->previous;
	filter->previous = raw;
	filter->have_previous = 1;

	filter->baseline_sum -= filter->baseline[filter->baseline_pos];
	filter->baseline[filter->baseline_pos] = raw;
	filter->baseline_sum += raw;
	filter->baseline_pos = (filter->baseline_pos + 1) % PIR_BASELINE_SAMPLES;

	if (rising && raw > filter->baseline_sum / PIR_BASELINE_SAMPLES + threshold) {
		filter->rising_samples = 0;
		return 1;
	}
	return 0;
}

static void pir_filter_reset(void)
{
	memset(g_pir_filter, 0, sizeof g_pir_filter);
	memset(g_pir_trigger, 0, sizeof g_pir_trigger);
	memset(g_pir_motion_time, 0, sizeof g_pir_motion_time);
}

static void update_pir(uint16_t left, uint16_t mid, uint16_t right)
{
	uint16_t raw[PIR_ZONES] = { left, mid, right };
	int changed = left != g_pir_raw[0] || mid != g_pir_raw[1] || right != g_pir_raw[2];
	int triggered;
	time_t now;

	g_pir_frames++;
	if (left || mid || right) g_pir_nonzero_frames++;
	for (int i = 0; i < PIR_ZONES; i++) {
		g_pir_raw[i] = raw[i];
		g_pir_trigger[i] = pir_filter_sample(i, raw[i]);
	}
	triggered = g_pir_trigger[0] || g_pir_trigger[1] || g_pir_trigger[2];

	if (changed || triggered || g_pir_frames == 1)
		monitor_emit("{\"event\":\"pir\",\"raw\":[%u,%u,%u],"
			"\"trigger\":[%d,%d,%d],\"frames\":%lu}",
			left, mid, right, g_pir_trigger[0], g_pir_trigger[1],
			g_pir_trigger[2], g_pir_frames);
	if (!g_zero_pir_warned && g_pir_frames >= 20 && !g_pir_nonzero_frames) {
		g_zero_pir_warned = 1;
		logv(LOG_WARNING, "PIR frames are valid but all samples are zero; check PIR board/connector");
		monitor_emit("{\"event\":\"diagnostic\",\"pir\":\"all_zero\","
			"\"frames\":%lu}", g_pir_frames);
	}
	if (!triggered) return;
	if (!active_policy_now(NULL, 0)) {
		g_pir_suppressed_events++;
		monitor_emit("{\"event\":\"motion_suppressed\",\"zones\":[%d,%d,%d],"
			"\"raw\":[%u,%u,%u],\"policy\":\"%s\"}",
			g_pir_trigger[0], g_pir_trigger[1], g_pir_trigger[2],
			left, mid, right, active_policy_name());
		return;
	}

	now = time(NULL);
	g_last_motion = now;
	g_pir_motion_events++;
	for (int i = 0; i < PIR_ZONES; i++)
		if (g_pir_trigger[i]) g_pir_motion_time[i] = now;
	char zones[32];
	snprintf(zones, sizeof zones, "%d %d %d",
		g_pir_trigger[0], g_pir_trigger[1], g_pir_trigger[2]);
	logv(LOG_INFO, "PIR motion L=%d M=%d R=%d (raw %u/%u/%u)",
		g_pir_trigger[0], g_pir_trigger[1], g_pir_trigger[2], left, mid, right);
	monitor_emit("{\"event\":\"motion\",\"zones\":[%d,%d,%d],"
		"\"raw\":[%u,%u,%u]}", g_pir_trigger[0], g_pir_trigger[1],
		g_pir_trigger[2], left, mid, right);
	run_hook(zones);
	if (g_light_mode == LIGHT_AUTO && g_light_level != g_bright_on)
		floodlight_set(g_bright_on, "motion");
}

/* ---- RX frame parser (MCU->SoC): 55 AA 43 LEN OP DATA.. SUMhi SUMlo ---- */
static void handle_frame(const uint8_t *f, int n)
{
	uint8_t op = f[4];
	if (g_verbose) {
		char hex[FRAME_MAX * 3]; int p = 0;
		for (int k = 0; k < n && k < FRAME_MAX; k++) p += sprintf(hex + p, "%02x ", f[k]);
		logv(LOG_DEBUG, "RX op=0x%02x: %s", op, hex);
	}
	if (op == OP_PIR_REPORT) {
		/* The CH554 returns three little-endian 16-bit PIR values in
		 * right/middle/left order.  Stock iCamera reverses the pairs when it
		 * presents the public left/middle/right values. */
		int dlen = n - 5 - 2;
		if (dlen < 6) return;
		uint16_t r = f[5] | ((uint16_t)f[6] << 8);
		uint16_t m = f[7] | ((uint16_t)f[8] << 8);
		uint16_t l = f[9] | ((uint16_t)f[10] << 8);
		update_pir(l, m, r);
	} else if (op == OP_BRIGHTNESS_REPORT) {
		int dlen = n - 5 - 2;
		if (dlen > 0 && f[5] <= 100) {
			int changed = g_light_level != f[5];
			g_light_level = f[5];
			if (changed)
				monitor_emit("{\"event\":\"light\",\"on\":%s,\"level\":%d,\"source\":\"mcu\"}",
					g_light_level ? "true" : "false", g_light_level);
		}
	}
}

/* Stateful reassembly buffer. Scans for 55 AA, validates LEN + checksum. */
static uint8_t  rxbuf[FRAME_MAX];
static int      rxlen = 0;

static void rx_feed(const uint8_t *in, int n)
{
	for (int i = 0; i < n; i++) {
		if (rxlen < FRAME_MAX) rxbuf[rxlen++] = in[i];
		else { memmove(rxbuf, rxbuf + 1, --rxlen); rxbuf[rxlen++] = in[i]; }

		/* need at least preamble+op+len */
		while (rxlen >= 4) {
			if (rxbuf[0] != RX_PRE0 || rxbuf[1] != RX_PRE1 || rxbuf[2] != TX_CLASS) {
				memmove(rxbuf, rxbuf + 1, --rxlen); /* resync */
				continue;
			}
			int total = rxbuf[3] + 4;             /* LEN + 4 */
			/* This CH554 firmware reports LEN=5 for its ten-byte brightness
			 * reply.  Account for that known one-byte error before deciding
			 * whether a complete frame is buffered. */
			if (rxlen >= 5 && rxbuf[4] == OP_BRIGHTNESS_REPORT && rxbuf[3] == 5)
				total++;
			if (total < 6 || total > FRAME_MAX) {  /* bogus length */
				memmove(rxbuf, rxbuf + 1, --rxlen);
				continue;
			}
			if (rxlen < total) break;              /* wait for more */
			uint16_t got = (rxbuf[total - 2] << 8) | rxbuf[total - 1];
			if (cksum(rxbuf, total - 2) == got)
				handle_frame(rxbuf, total);
			else
				logv(LOG_WARNING, "bad checksum (len %d)", total);
			memmove(rxbuf, rxbuf + total, rxlen - total);
			rxlen -= total;
		}
	}
}

/* ---- local control socket ---- */
static int parse_number(const char *text, int min, int max, int *value)
{
	char *end;
	long number;
	if (!text || !*text) return -1;
	errno = 0;
	number = strtol(text, &end, 10);
	if (errno || *end || number < min || number > max) return -1;
	*value = (int)number;
	return 0;
}

static void control_error(int fd, const char *usage)
{
	char line[CONTROL_MAX];
	int len = snprintf(line, sizeof line, "{\"error\":\"%s\"}\n", usage);
	if (len > 0) control_write(fd, line, len);
}

static int control_command(int slot, char *line)
{
	char *save = NULL;
	char *command = strtok_r(line, " \t\r\n", &save);
	char *arg1 = strtok_r(NULL, " \t\r\n", &save);
	char *arg2 = strtok_r(NULL, " \t\r\n", &save);
	char *extra = strtok_r(NULL, " \t\r\n", &save);
	int fd = g_clients[slot].fd;
	int level, seconds, value, start, end;

	if (!command) {
		control_error(fd, "empty command");
		return 0;
	}
	if (!strcmp(command, "status") && !arg1) {
		control_send_state(fd, "state");
		return 0;
	}
	if (!strcmp(command, "monitor") && !arg1) {
		g_clients[slot].monitor = 1;
		control_send_state(fd, "state");
		return 1;
	}
	if (!strcmp(command, "auto")) {
		if (extra || (arg1 && parse_number(arg1, 0, 86400, &seconds) != 0) ||
		    (arg2 && parse_number(arg2, 0, 100, &level) != 0)) {
			control_error(fd, "auto [hold_seconds [brightness]]");
			return 0;
		}
		if (arg1) g_motion_hold = seconds;
		if (arg2) g_bright_on = level;
		resume_auto("control");
		control_send_state(fd, "state");
		return 0;
	}
	if (!strcmp(command, "on")) {
		level = g_bright_on;
		seconds = 0;
		if (extra || (arg1 && parse_number(arg1, 1, 100, &level) != 0) ||
		    (arg2 && parse_number(arg2, 0, 86400, &seconds) != 0)) {
			control_error(fd, "on [brightness [seconds]]");
			return 0;
		}
		g_light_mode = LIGHT_MANUAL_ON;
		g_override_until = seconds ? time(NULL) + seconds : 0;
		floodlight_set(level, "manual");
		monitor_emit("{\"event\":\"mode\",\"mode\":\"manual_on\",\"duration\":%d}", seconds);
		control_send_state(fd, "state");
		return 0;
	}
	if (!strcmp(command, "off")) {
		seconds = 0;
		if (arg2 || extra || (arg1 && parse_number(arg1, 0, 86400, &seconds) != 0)) {
			control_error(fd, "off [seconds]");
			return 0;
		}
		g_light_mode = LIGHT_MANUAL_OFF;
		g_override_until = seconds ? time(NULL) + seconds : 0;
		floodlight_set(0, "manual");
		monitor_emit("{\"event\":\"mode\",\"mode\":\"manual_off\",\"duration\":%d}", seconds);
		control_send_state(fd, "state");
		return 0;
	}
	if (!strcmp(command, "sensitivity")) {
		if (!arg1 || arg2 || extra || parse_number(arg1, 0, 255, &value) != 0) {
			control_error(fd, "sensitivity 0..255");
			return 0;
		}
		g_pir_sensitivity = value;
		pir_filter_reset();
		monitor_emit("{\"event\":\"pir_config\",\"sensitivity\":%d,"
			"\"threshold\":%d}", g_pir_sensitivity, pir_threshold());
		control_send_state(fd, "state");
		return 0;
	}
	if (!strcmp(command, "zones")) {
		if (!arg1 || arg2 || extra || parse_number(arg1, 0, 7, &value) != 0) {
			control_error(fd, "zones 0..7 (bitmask: left=1 middle=2 right=4)");
			return 0;
		}
		g_pir_zone_mask = value;
		pir_filter_reset();
		monitor_emit("{\"event\":\"pir_config\",\"zone_mask\":%d}",
			g_pir_zone_mask);
		control_send_state(fd, "state");
		return 0;
	}
	if (!strcmp(command, "active")) {
		if (!arg1 || extra ||
		    ((!strcmp(arg1, "always") || !strcmp(arg1, "night")) && arg2) ||
		    (!strcmp(arg1, "clock") &&
		     (!arg2 || parse_active_window(arg2, &start, &end) != 0)) ||
		    (strcmp(arg1, "always") && strcmp(arg1, "night") &&
		     strcmp(arg1, "clock"))) {
			control_error(fd, "active always|night|clock HH:MM-HH:MM");
			return 0;
		}
		if (!strcmp(arg1, "clock")) {
			g_active_start = start;
			g_active_end = end;
		}
		set_active_policy(arg1);
		refresh_active_state("control");
		control_send_state(fd, "state");
		return 0;
	}

	control_error(fd, "status|monitor|auto|on|off|sensitivity|zones|active");
	return 0;
}

static int control_open(void)
{
	struct sockaddr_un address;
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) return -1;
	memset(&address, 0, sizeof address);
	address.sun_family = AF_UNIX;
	if (strlen(g_control_path) >= sizeof address.sun_path) {
		close(fd);
		errno = ENAMETOOLONG;
		return -1;
	}
	strcpy(address.sun_path, g_control_path);
	unlink(g_control_path);
	if (bind(fd, (struct sockaddr *)&address, sizeof address) != 0 ||
	    chmod(g_control_path, 0660) != 0 || listen(fd, CONTROL_CLIENTS) != 0) {
		int saved = errno;
		close(fd);
		unlink(g_control_path);
		errno = saved;
		return -1;
	}
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
	return fd;
}

static void control_accept(void)
{
	int fd = accept(g_control_fd, NULL, NULL);
	if (fd < 0) return;
	int slot;
	for (slot = 0; slot < CONTROL_CLIENTS; slot++)
		if (g_clients[slot].fd < 0) break;
	if (slot == CONTROL_CLIENTS) {
		control_error(fd, "too many clients");
		close(fd);
		return;
	}
	int flags = fcntl(fd, F_GETFL, 0);
	if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
	g_clients[slot].fd = fd;
	g_clients[slot].monitor = 0;
	g_clients[slot].len = 0;
}

static void control_read_client(int slot)
{
	struct control_client *client = &g_clients[slot];
	ssize_t count = read(client->fd, client->buf + client->len,
			     sizeof client->buf - 1 - client->len);
	if (count <= 0) {
		if (count == 0 || (errno != EAGAIN && errno != EINTR))
			control_close_client(slot);
		return;
	}
	client->len += count;
	client->buf[client->len] = '\0';
	char *newline = strchr(client->buf, '\n');
	if (!newline && client->len < (int)sizeof client->buf - 1) return;
	if (newline) *newline = '\0';
	if (!control_command(slot, client->buf)) control_close_client(slot);
}

static void control_cleanup(void)
{
	for (int i = 0; i < CONTROL_CLIENTS; i++) control_close_client(i);
	if (g_control_fd >= 0) close(g_control_fd);
	g_control_fd = -1;
	unlink(g_control_path);
}

static void control_client_usage(const char *program)
{
	fprintf(stderr,
		"Usage:\n"
		"  %s status\n"
		"  %s monitor\n"
		"  %s auto [hold_seconds [brightness]]\n"
		"  %s on [brightness [seconds]]\n"
		"  %s off [seconds]\n"
		"  %s sensitivity 0..255\n"
		"  %s zones 0..7\n"
		"  %s active always|night|clock HH:MM-HH:MM\n",
		program, program, program, program, program, program, program, program);
}

static int control_client_main(int argc, char **argv)
{
	if (argc < 2 || !strcmp(argv[1], "help") || !strcmp(argv[1], "-h") ||
	    !strcmp(argv[1], "--help")) {
		control_client_usage(argv[0]);
		return argc < 2 ? 1 : 0;
	}
	const char *path = getenv("FLOODLIGHTD_SOCKET");
	if (!path || !*path) path = CONTROL_SOCKET;
	struct sockaddr_un address;
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0) {
		perror("floodlightctl socket");
		return 1;
	}
	memset(&address, 0, sizeof address);
	address.sun_family = AF_UNIX;
	if (strlen(path) >= sizeof address.sun_path) {
		fprintf(stderr, "floodlightctl: socket path is too long\n");
		close(fd);
		return 1;
	}
	strcpy(address.sun_path, path);
	if (connect(fd, (struct sockaddr *)&address, sizeof address) != 0) {
		fprintf(stderr, "floodlightctl: cannot connect to %s: %s\n", path, strerror(errno));
		close(fd);
		return 1;
	}

	char command[CONTROL_MAX];
	int len = 0;
	for (int i = 1; i < argc; i++) {
		int written = snprintf(command + len, sizeof command - len, "%s%s",
				       i == 1 ? "" : " ", argv[i]);
		if (written < 0 || written >= (int)sizeof command - len - 1) {
			fprintf(stderr, "floodlightctl: command is too long\n");
			close(fd);
			return 1;
		}
		len += written;
	}
	command[len++] = '\n';
	if (control_write(fd, command, len) != 0) {
		perror("floodlightctl write");
		close(fd);
		return 1;
	}

	char reply[CONTROL_MAX];
	ssize_t count;
	while ((count = read(fd, reply, sizeof reply)) > 0)
		if (write(STDOUT_FILENO, reply, count) < 0) break;
	close(fd);
	return count < 0 ? 1 : 0;
}

static void usage(const char *p)
{
	fprintf(stderr,
	  "Usage: %s [opts]\n"
	  "  -d DEV      serial device (default /dev/ttyS2)\n"
	  "  -b BAUD     baud: 9600|115200 (default 115200)\n"
	  "  -B LEVEL    brightness on motion 0-100 (default 100)\n"
	  "  -m MODE     set-brightness mode byte (default 0)\n"
	  "  -r RAMP     ramp duration in 100ms units (default 5)\n"
	  "  -t SECS     seconds to hold flood after last motion (default 30)\n"
	  "  -p MS       PIR poll interval ms, 0=passive (default 500)\n"
	  "  -S LEVEL    PIR sensitivity 0-255 (stock default 255)\n"
	  "  -z MASK     PIR zone mask: left=1 middle=2 right=4 (default 7)\n"
	  "  -a POLICY   automatic action policy: always|night|clock\n"
	  "  -w WINDOW   local clock window HH:MM-HH:MM (default 18:00-06:00)\n"
	  "  -D PATH     day/night state file (default /run/thingino/daynight_mode)\n"
	  "  -H PATH     motion hook script (default /etc/floodlightd/motion.sh)\n"
	  "  -s PATH     control socket (default /run/floodlightd.sock)\n"
	  "  -f          run in foreground\n"
	  "  -v          verbose (hex frames)\n", p);
}

int main(int argc, char **argv)
{
	const char *program = strrchr(argv[0], '/');
	program = program ? program + 1 : argv[0];
	if (strstr(program, "floodlightctl")) return control_client_main(argc, argv);

	for (int i = 0; i < CONTROL_CLIENTS; i++) g_clients[i].fd = -1;
	int c;
	int option_error = 0;
	while ((c = getopt(argc, argv, "d:b:B:m:r:t:p:S:z:a:w:D:H:s:fvh")) != -1) {
		switch (c) {
		case 'd': g_tty = optarg; break;
		case 'b': g_baud = (atoi(optarg) == 9600) ? B9600 : B115200; break;
		case 'B': g_bright_on = atoi(optarg); break;
		case 'm': g_bright_mode = atoi(optarg); break;
		case 'r': g_ramp_100ms = atoi(optarg); break;
		case 't': g_motion_hold = atoi(optarg); break;
		case 'p': g_poll_ms = atoi(optarg); break;
		case 'S': g_pir_sensitivity = atoi(optarg); break;
		case 'z': g_pir_zone_mask = atoi(optarg); break;
		case 'a':
			if (set_active_policy(optarg) != 0) option_error = 1;
			break;
		case 'w':
			if (parse_active_window(optarg, &g_active_start, &g_active_end) != 0)
				option_error = 1;
			break;
		case 'D': g_daynight_file = optarg; break;
		case 'H': g_hook = optarg; break;
		case 's': g_control_path = optarg; break;
		case 'f': g_foreground = 1; break;
		case 'v': g_verbose = 1; break;
		default: usage(argv[0]); return c == 'h' ? 0 : 1;
		}
	}
	if (g_pir_sensitivity < 0 || g_pir_sensitivity > 255 ||
	    g_pir_zone_mask < 0 || g_pir_zone_mask > 7 ||
	    !g_daynight_file || !*g_daynight_file || option_error) {
		usage(argv[0]);
		return 1;
	}

	if (!g_foreground) openlog("floodlightd", LOG_PID, LOG_DAEMON);
	signal(SIGINT, on_sig);
	signal(SIGTERM, on_sig);
	signal(SIGCHLD, SIG_IGN);   /* auto-reap motion-hook children */
	signal(SIGPIPE, SIG_IGN);

	g_fd = tty_open(g_tty, g_baud);
	if (g_fd < 0) {
		logv(LOG_ERR, "open %s: %s", g_tty, strerror(errno));
		return 1;
	}
	logv(LOG_INFO, "floodlightd up on %s @ %s", g_tty,
	     g_baud == B9600 ? "9600" : "115200");
	g_control_fd = control_open();
	if (g_control_fd < 0) {
		logv(LOG_ERR, "control socket %s: %s", g_control_path, strerror(errno));
		close(g_fd);
		return 1;
	}

	/* ask the MCU for its firmware version once (handy in logs) */
	mcu_send(OP_GET_SOFTWARE, NULL, 0);
	/* Synchronize status with the MCU's current light state. */
	mcu_send(OP_GET_BRIGHTNESS, NULL, 0);
	refresh_active_state("startup");

	struct timespec last_poll = {0};
	time_t last_active_check = time(NULL);
	while (g_run) {
		fd_set rfds;
		FD_ZERO(&rfds);
		FD_SET(g_fd, &rfds);
		FD_SET(g_control_fd, &rfds);
		int max_fd = g_fd > g_control_fd ? g_fd : g_control_fd;
		for (int i = 0; i < CONTROL_CLIENTS; i++) {
			if (g_clients[i].fd >= 0) {
				FD_SET(g_clients[i].fd, &rfds);
				if (g_clients[i].fd > max_fd) max_fd = g_clients[i].fd;
			}
		}
		struct timeval tv = { .tv_sec = 0, .tv_usec = 200000 };
		int rc = select(max_fd + 1, &rfds, NULL, NULL, &tv);
		if (rc < 0) { if (errno == EINTR) continue; break; }

		if (rc > 0 && FD_ISSET(g_fd, &rfds)) {
			uint8_t buf[128];
			int r = read(g_fd, buf, sizeof buf);
			if (r > 0) {
				if (g_verbose) {
					char hex[sizeof buf * 3 + 1];
					int p = 0;
					for (int k = 0; k < r; k++)
						p += snprintf(hex + p, sizeof hex - p, "%02x ", buf[k]);
					logv(LOG_DEBUG, "RX raw: %s", hex);
				}
				rx_feed(buf, r);
			}
			else if (r == 0 || (r < 0 && errno != EAGAIN && errno != EINTR))
				logv(LOG_WARNING, "ttyS2 read: %s", strerror(errno));
		}
		if (rc > 0 && FD_ISSET(g_control_fd, &rfds)) control_accept();
		for (int i = 0; i < CONTROL_CLIENTS; i++)
			if (g_clients[i].fd >= 0 && FD_ISSET(g_clients[i].fd, &rfds))
				control_read_client(i);

		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		time_t wall_now = time(NULL);

		if (wall_now != last_active_check) {
			refresh_active_state("clock");
			last_active_check = wall_now;
		}

		/* poll PIR value on cadence (active mode) */
		if (g_poll_ms > 0) {
			long dms = (now.tv_sec - last_poll.tv_sec) * 1000 +
			           (now.tv_nsec - last_poll.tv_nsec) / 1000000;
			if (dms >= g_poll_ms) { mcu_send(OP_GET_PIR, NULL, 0); last_poll = now; }
		}

		/* Timed manual overrides return to PIR/auto mode. */
		if (g_light_mode != LIGHT_AUTO && g_override_until &&
		    wall_now >= g_override_until) {
			logv(LOG_INFO, "manual override expired; resuming auto mode");
			resume_auto("timer");
		}

		/* turn flood off after the PIR hold window expires */
		if (g_light_mode == LIGHT_AUTO && g_light_level > 0 && g_motion_hold > 0 &&
		    wall_now - g_last_motion >= g_motion_hold) {
			floodlight_set(0, "motion_timeout");
			logv(LOG_INFO, "flood off (motion hold expired)");
		}
	}

	if (g_light_level > 0) floodlight_set(0, "shutdown");
	control_cleanup();
	close(g_fd);
	logv(LOG_INFO, "floodlightd exiting");
	if (!g_foreground) closelog();
	return 0;
}
