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
//   MCU -> SoC : 55 AA OP  LEN [DATA..] SUMhi SUMlo     (total = LEN+4)
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
#define OP_PIR_REPORT     0xBD

#define FRAME_MAX 256
#define CONTROL_SOCKET "/run/floodlightd.sock"
#define CONTROL_MAX 256
#define CONTROL_CLIENTS 8

enum light_mode {
	LIGHT_AUTO,
	LIGHT_MANUAL_ON,
	LIGHT_MANUAL_OFF,
};

struct control_client {
	int fd;
	int monitor;
	int len;
	char buf[CONTROL_MAX];
};

/* ---- config (overridable via CLI) ---- */
static const char *g_tty   = "/dev/ttyS2";
static speed_t     g_baud  = B115200;
static int         g_bright_on   = 100;   /* brightness when motion fires   */
static int         g_bright_mode = 0;     /* set-brightness mode byte        */
static int         g_ramp_100ms  = 5;     /* ramp duration, units of 100 ms  */
static int         g_motion_hold = 30;    /* seconds to hold flood after motion */
static int         g_poll_ms     = 500;   /* PIR poll cadence (0 = passive)   */
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
static uint8_t g_pir[3];

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

static int state_json(char *buf, size_t size, const char *event)
{
	return snprintf(buf, size,
		"{\"event\":\"%s\",\"mode\":\"%s\",\"light\":%s,"
		"\"level\":%d,\"auto_brightness\":%d,\"hold\":%d,"
		"\"override_remaining\":%ld,\"pir\":[%u,%u,%u]}\n",
		event, light_mode_name(), g_light_level > 0 ? "true" : "false",
		g_light_level, g_bright_on, g_motion_hold, override_remaining(),
		g_pir[0], g_pir[1], g_pir[2]);
}

static int control_write(int fd, const char *buf, size_t len)
{
	while (len) {
		ssize_t written = send(fd, buf, len, MSG_NOSIGNAL);
		if (written < 0) {
			if (errno == EINTR) continue;
			return -1;
		}
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

	struct termios t;
	if (tcgetattr(fd, &t) != 0) { close(fd); return -1; }
	cfmakeraw(&t);
	t.c_cflag |= (CLOCAL | CREAD);
	t.c_cflag &= ~CRTSCTS;
	t.c_cc[VMIN]  = 0;
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

static void resume_auto(const char *source)
{
	g_light_mode = LIGHT_AUTO;
	g_override_until = 0;
	if (g_pir[0] || g_pir[1] || g_pir[2]) {
		g_last_motion = time(NULL);
		floodlight_set(g_bright_on, source);
	} else {
		floodlight_set(0, source);
	}
	monitor_emit("{\"event\":\"mode\",\"mode\":\"auto\",\"source\":\"%s\"}", source);
}

static void update_pir(uint8_t left, uint8_t mid, uint8_t right)
{
	int was_active = g_pir[0] || g_pir[1] || g_pir[2];
	int active = left || mid || right;
	int changed = left != g_pir[0] || mid != g_pir[1] || right != g_pir[2];
	g_pir[0] = left;
	g_pir[1] = mid;
	g_pir[2] = right;

	if (changed)
		monitor_emit("{\"event\":\"pir\",\"left\":%u,\"middle\":%u,\"right\":%u}",
			left, mid, right);
	if (!active) return;

	g_last_motion = time(NULL);
	if (!was_active) {
		char zones[32];
		snprintf(zones, sizeof zones, "%u %u %u", left, mid, right);
		logv(LOG_INFO, "PIR motion L=%u M=%u R=%u", left, mid, right);
		monitor_emit("{\"event\":\"motion\",\"left\":%u,\"middle\":%u,\"right\":%u}",
			left, mid, right);
		run_hook(zones);
	}
	if (g_light_mode == LIGHT_AUTO && g_light_level != g_bright_on)
		floodlight_set(g_bright_on, "motion");
}

/* ---- RX frame parser (MCU->SoC): 55 AA OP LEN DATA.. SUMhi SUMlo ---- */
static void handle_frame(const uint8_t *f, int n)
{
	uint8_t op = f[2];
	if (g_verbose) {
		char hex[FRAME_MAX * 3]; int p = 0;
		for (int k = 0; k < n && k < FRAME_MAX; k++) p += sprintf(hex + p, "%02x ", f[k]);
		logv(LOG_DEBUG, "RX op=0x%02x: %s", op, hex);
	}
	if (op == OP_PIR_REPORT) {
		/* payload = DATA between byte[4] and n-2. Zone layout confirmed as
		 * left/middle/right; treat any nonzero zone as motion. */
		int dlen = n - 4 - 2;
		uint8_t l = dlen > 0 ? f[4] : 0;
		uint8_t m = dlen > 1 ? f[5] : 0;
		uint8_t r = dlen > 2 ? f[6] : 0;
		update_pir(l, m, r);
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
			if (rxbuf[0] != RX_PRE0 || rxbuf[1] != RX_PRE1) {
				memmove(rxbuf, rxbuf + 1, --rxlen); /* resync */
				continue;
			}
			int total = rxbuf[3] + 4;             /* LEN + 4 */
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
	int level, seconds;

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

	control_error(fd, "status|monitor|auto|on|off");
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
		"  %s off [seconds]\n",
		program, program, program, program, program);
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
	while ((c = getopt(argc, argv, "d:b:B:m:r:t:p:H:s:fvh")) != -1) {
		switch (c) {
		case 'd': g_tty = optarg; break;
		case 'b': g_baud = (atoi(optarg) == 9600) ? B9600 : B115200; break;
		case 'B': g_bright_on = atoi(optarg); break;
		case 'm': g_bright_mode = atoi(optarg); break;
		case 'r': g_ramp_100ms = atoi(optarg); break;
		case 't': g_motion_hold = atoi(optarg); break;
		case 'p': g_poll_ms = atoi(optarg); break;
		case 'H': g_hook = optarg; break;
		case 's': g_control_path = optarg; break;
		case 'f': g_foreground = 1; break;
		case 'v': g_verbose = 1; break;
		default: usage(argv[0]); return c == 'h' ? 0 : 1;
		}
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

	struct timespec last_poll = {0};
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
			if (r > 0) rx_feed(buf, r);
			else if (r == 0 || (r < 0 && errno != EAGAIN && errno != EINTR))
				logv(LOG_WARNING, "ttyS2 read: %s", strerror(errno));
		}
		if (rc > 0 && FD_ISSET(g_control_fd, &rfds)) control_accept();
		for (int i = 0; i < CONTROL_CLIENTS; i++)
			if (g_clients[i].fd >= 0 && FD_ISSET(g_clients[i].fd, &rfds))
				control_read_client(i);

		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);

		/* poll PIR value on cadence (active mode) */
		if (g_poll_ms > 0) {
			long dms = (now.tv_sec - last_poll.tv_sec) * 1000 +
			           (now.tv_nsec - last_poll.tv_nsec) / 1000000;
			if (dms >= g_poll_ms) { mcu_send(OP_GET_PIR, NULL, 0); last_poll = now; }
		}

		/* Timed manual overrides return to PIR/auto mode. */
		if (g_light_mode != LIGHT_AUTO && g_override_until &&
		    time(NULL) >= g_override_until) {
			logv(LOG_INFO, "manual override expired; resuming auto mode");
			resume_auto("timer");
		}

		/* turn flood off after the PIR hold window expires */
		if (g_light_mode == LIGHT_AUTO && g_light_level > 0 && g_motion_hold > 0 &&
		    time(NULL) - g_last_motion >= g_motion_hold) {
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
