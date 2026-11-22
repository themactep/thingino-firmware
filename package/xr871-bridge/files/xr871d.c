/*
 * xr871d - keep-alive / control daemon for the XR871 WiFi co-processor
 * found on battery cameras such as the ABUS PPIC90520 (Ingenic T30 + XR871).
 *
 * On these boards the XR871 owns WiFi and the T30 power rail. It powers the
 * T30 up on a wake event and power-cycles it again if the T30 does not send
 * a heartbeat within ~6 s. This daemon speaks the UART side of that protocol
 * so the T30 stays on:
 *
 *   - heartbeat (cmd 0xa9) every 3 s, starting immediately
 *   - hello (cmd 0x00) every 2 s until the XR871 answers
 *   - answers the XR871 requests the way the vendor application does
 *   - takes the wall clock from the XR871 (cmd 0x40, ms since epoch)
 *
 * Frame (both directions), little endian:
 *   0  u32 magic 0x55aa55aa (bytes aa 55 aa 55)
 *   4  u16 payload length
 *   6  u8  command
 *   7  u8  0x01
 *   8  u16 0
 *  10  u16 parameter / result
 *  12  payload
 * The T30 side always writes 64-byte frames (payload <= 116 bytes).
 *
 * Signals: SIGUSR1 = ask the XR871 to power the T30 off (cmd 0x83, 0)
 *          SIGUSR2 = ask the XR871 to keep the T30 on   (cmd 0x83, 1)
 *
 * Control: "xr871d -c '<command>'" sends a command to the running daemon
 * (abstract unix socket @xr871d, no filesystem needed this early):
 *   sleep [seconds]  sync, then ask the XR871 to switch the T30 off; with
 *                    the bridge firmware it is powered up again on PIR, a
 *                    key, Wake-on-LAN or after <seconds>
 *   stay             withdraw a sleep request (within the grace time)
 *   wifi             re-send the WiFi credentials
 *   probe            find the XR871 pin wired to the SPI ready line (GPIO 77)
 * and, with the bridge firmware (output goes back to the -c caller):
 *   status           battery, USB, WiFi/RSSI, versions, wake reason, uptime,
 *                    link counters (cmd 0xd0)
 *   mcu <cmd> <val> [force]
 *                    send a raw 2-byte message to the power MCU (cmd 0xd1)
 *                    and print what it sends back within 1 s; messages that
 *                    switch the T30 (or the board) off need "force"
 *   gpio <PAn> <0|1|in|blink|off> [seconds]
 *                    drive / read an XR871 pin (cmd 0xd3); protected pins
 *                    are refused by the XR871 itself; levels fall back after
 *                    [seconds] (default 30)
 *   gpio scan [seconds] PAn [PAn ...]
 *                    blink the named pins one after the other (3 s each)
 *                    to find e.g. a LED; no default list, the roles of
 *                    PA6/11/13 are unknown
 *   led blue 0|1     blue status LED (on while a video stream runs)
 *   fwupdate <file> [--commit] [--reboot] [--force-stage]
 *   fwupdate --info | --abort | --commit
 *                    write an XR871 application image (full 2 MiB flash
 *                    image or the chain from 0x8000) into the inactive image
 *                    slot over the UART, verify it, and only with --commit
 *                    switch the boot config to it (cmds 0xd8..0xdc)
 * XR871 log lines (cmd 0xd4) go to syslog with the tag "xr871", MCU events
 * (cmd 0xd2) to the daemon log.
 * The reason for the current power-on (cmd 0x85) is written to
 * /run/xr871d.wake: cold, pir, key, wlan, timer or 0x... for stock values.
 * PIR motion (cmd 0xcd from the bridge firmware while the T30 runs, or a
 * power-on with wake source pir) runs "/usr/libexec/xr871/pir motion|wake"
 * detached, if that hook exists (board policy, e.g. the night light), and
 * records the time in /run/xr871d.last_motion. Once a minute it runs
 * "/usr/libexec/xr871/standby tick" (board standby policy), if it exists.
 *
 * With the ABUS bridge firmware on the XR871 (it answers our 0xf1 marker),
 * xr871d also
 *   - sends the station credentials from /etc/wpa_supplicant.conf (first
 *     network block; ssid + psk, 64-hex PMK or passphrase) as cmd 0xc0; the
 *     XR871 stores them and joins on its own, also while the T30 sleeps
 *   - finds the ready line once (cmd 0xc4: raise one candidate XR871 pin at
 *     a time, watch GPIO 77) and remembers it in /etc/xr871d.conf
 *     (ready_pin=N); every boot it tells the XR871 with cmd 0xc5. A pin that
 *     resets the T30 while probed is recorded as bad and never probed again.
 *
 * Log goes to /dev/kmsg; a one-line-per-boot record is appended to
 * /overlay/xr871d.log once the overlay is mounted, so a boot can be
 * verified from a flash dump without a serial console.
 */

#include <errno.h>
#include <stddef.h>
#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <syslog.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

#define VERSION "0.7"
#define WIFI_OP_FILE "/run/xr871d.wifiop"
#define WIFI_MODE_FILE "/run/xr871d.wifimode"
#define SCAN_FILE "/run/xr871d.scan"
#define SCAN_TMP "/run/xr871d.scan.tmp"
#define BATTERY_FILE "/run/xr871d.battery"
#define PIR_HOOK "/usr/libexec/xr871/pir"
#define STANDBY_HOOK "/usr/libexec/xr871/standby"
#define MOTION_FILE "/run/xr871d.last_motion"
#define STANDBY_TICK_MS 60000
#define FRAME_LEN 64
#define HDR_LEN 12
#define MAX_PAYLOAD 0x74
#define MAX_RX_PAYLOAD 0xf4
#define MAGIC 0x55aa55aaU

#define HEARTBEAT_MS 3000
#define HELLO_MS 2000

static const char *dev = "/dev/ttyS0";
static int fd = -1;
static int verbose;
static volatile sig_atomic_t want_power = -1;
static volatile sig_atomic_t stop;

/* counters for the persistent boot record */
static unsigned long n_tx_hb, n_rx, n_rx_bad;
static long first_reply_ms = -1;
static int clock_set;
static int boot_logged;
static int ctl = -1;
static int bridge_fw;		/* XR871 runs the ABUS bridge firmware */
static int ready_pin = -1;
#define CONF "/etc/xr871d.conf"
#define READY_GPIO 77
static void send_wifi(void);
static void wifi_op_done(uint16_t param);
static void write_str(const char *path, const char *s);

/* run PIR_HOOK <arg> fully detached (double fork, no zombie, no wait) */
static void run_hook(const char *hook, const char *arg)
{
	pid_t p;

	if (access(hook, X_OK) != 0)
		return;
	p = fork();
	if (p == 0) {
		if (fork() == 0) {
			int fd = open("/dev/null", O_RDWR);

			setsid();
			if (fd >= 0) {
				dup2(fd, 0);
				dup2(fd, 1);
				dup2(fd, 2);
				if (fd > 2)
					close(fd);
			}
			execl(hook, hook, arg, (char *)NULL);
			_exit(127);
		}
		_exit(0);
	}
	if (p > 0)
		waitpid(p, NULL, 0);
}

/* PIR: remember the time (seconds since boot, for the standby policy) and
 * run the board hook (night light) */
static void run_pir_hook(const char *arg)
{
	struct timespec ts;
	char t[24];

	clock_gettime(CLOCK_MONOTONIC, &ts);
	snprintf(t, sizeof(t), "%ld\n", (long)ts.tv_sec);
	write_str(MOTION_FILE, t);
	run_hook(PIR_HOOK, arg);
}
static void scan_entry(uint16_t idx, const uint8_t *e, int len);
static void send_ap(const char *arg);
static void write_str(const char *path, const char *s);
static void probe_ready(void);
static uint32_t wake_reason;
static int wake_pending_write;
static long next_hb;		/* next heartbeat due (also kept during long commands) */
static const char *xlog_file;	/* -l: XR871 log lines to a file instead of syslog */
static void handle_ext(uint8_t cmd, uint16_t param, const uint8_t *p, uint16_t plen);
static void ext_enable(void);

static long now_ms(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000L + ts.tv_nsec / 1000000L;
}

static void logk(const char *fmt, ...)
{
	char buf[256];
	int n;
	va_list ap;
	int k;

	n = snprintf(buf, sizeof(buf), "<6>xr871d: ");
	va_start(ap, fmt);
	n += vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	va_end(ap);
	if (n >= (int)sizeof(buf))
		n = sizeof(buf) - 1;

	k = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	if (k >= 0) {
		if (write(k, buf, n) < 0) { /* best effort */ }
		close(k);
	}
	if (verbose)
		fprintf(stderr, "%s\n", buf + 3);
}

static int uart_open(void)
{
	struct termios t;
	int f = open(dev, O_RDWR | O_NOCTTY | O_CLOEXEC);

	if (f < 0)
		return -1;
	if (tcgetattr(f, &t) < 0) {
		close(f);
		return -1;
	}
	cfmakeraw(&t);
	t.c_cflag &= ~(CSTOPB | PARENB | CRTSCTS);
	t.c_cflag |= CS8 | CLOCAL | CREAD;
	t.c_cc[VMIN] = 0;
	t.c_cc[VTIME] = 0;
	cfsetispeed(&t, B115200);
	cfsetospeed(&t, B115200);
	if (tcsetattr(f, TCSANOW, &t) < 0) {
		close(f);
		return -1;
	}
	tcflush(f, TCIOFLUSH);
	return f;
}

/* CRC-16/CCITT-FALSE over header bytes 4..7 and 10.. (len, cmd, flag,
 * param, payload). Frames from our xr871d carry it in bytes 8..9 with flag
 * byte 7 = 0x02 (the vendor value is 0x01, bytes 8..9 zero). */
static uint16_t frame_crc(const uint8_t *f, int plen)
{
	uint16_t crc = 0xffff;
	int i, j;

	for (i = 4; i < HDR_LEN + plen; i++) {
		if (i == 8 || i == 9)
			continue;
		crc ^= (uint16_t)f[i] << 8;
		for (j = 0; j < 8; j++)
			crc = crc & 0x8000 ? (uint16_t)(crc << 1) ^ 0x1021 : (uint16_t)(crc << 1);
	}
	return crc;
}

static int send_frame(uint8_t cmd, uint16_t param, const void *payload, size_t len)
{
	/* the vendor app always writes 64 bytes; longer frames only for the
	 * bridge firmware commands (its parser takes up to 0xf4 bytes) */
	uint8_t f[HDR_LEN + MAX_RX_PAYLOAD];
	size_t off = 0, total;

	if (fd < 0)
		return -1;
	if (len > MAX_RX_PAYLOAD)
		len = MAX_RX_PAYLOAD;
	total = HDR_LEN + len < FRAME_LEN ? FRAME_LEN : HDR_LEN + len;
	memset(f, 0, sizeof(f));
	f[0] = 0xaa; f[1] = 0x55; f[2] = 0xaa; f[3] = 0x55;
	f[4] = len & 0xff; f[5] = len >> 8;
	f[6] = cmd;
	f[7] = 0x01;
	f[10] = param & 0xff; f[11] = param >> 8;
	if (len)
		memcpy(f + HDR_LEN, payload, len);
	if (bridge_fw) {
		/* our firmware checks it; the vendor firmware never sees 0x02 */
		uint16_t crc;

		f[7] = 0x02;
		crc = frame_crc(f, (int)len);
		f[8] = crc & 0xff;
		f[9] = crc >> 8;
	}

	while (off < total) {
		ssize_t w = write(fd, f + off, total - off);
		if (w < 0) {
			if (errno == EINTR || errno == EAGAIN)
				continue;
			return -1;
		}
		off += w;
	}
	/* let the frame leave and leave a short gap before the next one: the
	 * XR871 must not get bursts of several frames back to back */
	tcdrain(fd);
	usleep(2000);
	return 0;
}

/* Version record the vendor application reports (cmd 0x12, 32 bytes). */
static void send_version(void)
{
	uint8_t v[32];

	memset(v, 0, sizeof(v));
	memcpy(v, "D819-T30", 8);
	memcpy(v + 16, "0.0.2-18021", 11);
	send_frame(0x12, 0, v, sizeof(v));
}

static void set_clock_ms(const uint8_t *p)
{
	uint64_t ms = 0;
	struct timeval tv;
	int i;

	for (i = 7; i >= 0; i--)
		ms = (ms << 8) | p[i];
	/* only accept something after 2020-01-01 */
	if (ms < 1577836800000ULL)
		return;
	tv.tv_sec = ms / 1000;
	tv.tv_usec = (ms % 1000) * 1000;
	if (settimeofday(&tv, NULL) == 0) {
		clock_set = 1;
		logk("clock set from XR871: %lld", (long long)tv.tv_sec);
	}
}

static void handle_frame(const uint8_t *b, int len)
{
	uint8_t cmd = b[6];
	uint16_t plen = b[4] | (b[5] << 8);
	uint16_t param = len >= HDR_LEN ? (b[10] | (b[11] << 8)) : 0;

	n_rx++;
	if (first_reply_ms < 0) {
		first_reply_ms = now_ms();
		logk("XR871 answered (first cmd 0x%02x)", cmd);
		/* marker the XR871 logs as an unknown command: proves we booted */
		send_frame(0xf1, 0, "thingino xr871d " VERSION, 20);
	}
	if (verbose)
		logk("rx cmd 0x%02x len %u param %u", cmd, plen, param);

	switch (cmd) {
	case 0x02:	/* ping */
	case 0x13:	/* factory default request: acknowledged, not executed */
	case 0x18:	/* basic parameters */
	case 0x21:	/* force I-frame */
	case 0x50:
	case 0xa2:	/* audio test */
		send_frame(cmd, 0, NULL, 0);
		break;
	case 0x12:	/* version */
	case 0x85:	/* wake / boot source (payload u32) */
		if (cmd == 0x85 && plen >= 4) {
			wake_reason = b[12] | b[13] << 8 | b[14] << 16 | (uint32_t)b[15] << 24;
			wake_pending_write = 1;
			logk("wake source 0x%08x", (unsigned)wake_reason);
			if (wake_reason == 0x101)
				run_pir_hook("wake");
		}
		send_version();
		break;
	case 0x19:	/* version + uuid + parameters */
		send_version();
		send_frame(cmd, 0, NULL, 0);
		break;
	case 0x40:	/* info, carries wall clock in ms */
		if (plen >= 8 && len >= HDR_LEN + 8)
			set_clock_ms(b + HDR_LEN);
		send_frame(cmd, 1, NULL, 0);
		break;
	case 0xf1:	/* bridge firmware answers our marker */
		if (!bridge_fw) {
			bridge_fw = 1;
			logk("XR871 runs the bridge firmware (%.*s)", plen > 16 ? 16 : plen,
			     (const char *)b + HDR_LEN);
			ext_enable();
		}
		break;
	case 0xd0: case 0xd1: case 0xd2: case 0xd3: case 0xd4:
	case 0xd8: case 0xd9: case 0xda: case 0xdb: case 0xdc:
		/* extension replies / events: never echoed back */
		handle_ext(cmd, param, len > HDR_LEN ? b + HDR_LEN : b, len > HDR_LEN ? plen : 0);
		break;
	case 0xc0:
		logk("XR871: wifi config %s", param == 1 ? "stored" : param == 0 ? "unchanged" : "rejected");
		break;
	case 0xc4:
		break;		/* probe acks, results are read from GPIO 77 */
	case 0xc6:
	case 0xc7:
	case 0xc8:
		logk("XR871: wifi request 0x%02x %s", cmd, param ? "refused" : "accepted");
		if (param)
			wifi_op_done(0xff00 | (cmd == 0xc6 ? 1 : cmd == 0xc7 ? 0 : 2));
		break;
	case 0xca:	/* wifi op finished: param = op | result << 8 */
		wifi_op_done(param);
		break;
	case 0xcc:	/* battery: u16 mV, u8 soc, s8 deg C, u8 flags[, u16 t2e, u16 t2f] */
		if (plen >= 5 && len >= HDR_LEN + 5) {
			const uint8_t *p = b + HDR_LEN;
			unsigned t2e = 0xffff;
			char t[160], e[32] = "";

			if (plen >= 9 && len >= HDR_LEN + 9)
				t2e = p[5] | p[6] << 8;
			/* estimate on battery below 100 % only, see xr871d -c status */
			if (t2e != 0xffff && !(p[4] & 4) && p[2] < 100)
				snprintf(e, sizeof(e), "t2e_min=%u\n", t2e);
			snprintf(t, sizeof(t), "vbat_mv=%u\nsoc=%u\ntemp_c=%d\nusb=%d\ncharging=%d\n%supdated=%ld\n",
				 (unsigned)(p[0] | p[1] << 8), p[2], (int8_t)p[3],
				 !!(p[4] & 4), !!(p[4] & 8), e, (long)time(NULL));
			write_str(BATTERY_FILE, t);
		}
		break;
	case 0xcd:	/* PIR motion while the T30 runs */
		logk("PIR motion (0x%02x)", param);
		run_pir_hook("motion");
		break;
	case 0xcb:	/* one scan result */
		if (plen >= 10 && len >= HDR_LEN + plen)
			scan_entry(param, b + HDR_LEN, plen);
		break;
	case 0xc5:
		logk("XR871: ready line PA%u %s", param, param == 0xffff ? "rejected" : "in use");
		break;
	case 0x83:	/* power state notice / sleep acknowledged */
		logk("XR871: power off in %u ms", param);
		break;
	case 0xd5:	/* LED request accepted (param = LED bits): nothing to do */
		break;
	case 0xa4:	/* firmware push to the T30: never accepted here */
		logk("ignoring XR871 firmware update request");
		break;
	default:
		send_frame(cmd, 1, NULL, 0);
		break;
	}
}

/*
 * Byte-wise parser after the vendor UartDataParse(), with one difference:
 * a frame without payload is taken as 12 bytes (our bridge firmware puts
 * the parameter at offset 10), but if the next magic or a pause comes
 * after only 8 bytes (stock style) it is handled as an 8-byte frame.
 */
static uint8_t pbuf[HDR_LEN + MAX_RX_PAYLOAD];
static int phave = -1;	/* -1: hunting for magic */

static int pending_short(void)
{
	return phave >= 8 && phave < HDR_LEN && (pbuf[4] | (pbuf[5] << 8)) == 0;
}

static void parse_flush(void)
{
	if (pending_short()) {
		handle_frame(pbuf, 8);
		phave = -1;
	}
}

static void parse(const uint8_t *in, int n)
{
	static uint32_t acc;
	int i;

	for (i = 0; i < n; i++) {
		uint8_t c = in[i];

		acc = (acc >> 8) | ((uint32_t)c << 24);
		if (acc == MAGIC) {
			if (pending_short())
				handle_frame(pbuf, 8);	/* bytes 8.. were this magic */
			pbuf[0] = 0xaa; pbuf[1] = 0x55; pbuf[2] = 0xaa; pbuf[3] = 0x55;
			phave = 4;
			continue;
		}
		if (phave < 0)
			continue;
		pbuf[phave++] = c;
		if (phave >= 8) {
			uint16_t plen = pbuf[4] | (pbuf[5] << 8);

			if (plen > MAX_RX_PAYLOAD) {
				n_rx_bad++;
				phave = -1;
			} else if (phave == HDR_LEN + plen) {
				handle_frame(pbuf, phave);
				phave = -1;
			}
		}
	}
}

static void boot_record(void)
{
	struct stat st;
	FILE *f;
	time_t t;

	if (boot_logged || first_reply_ms < 0)
		return;
	if (stat("/overlay/etc", &st) != 0)
		return;	/* overlay not mounted yet */
	if (stat("/overlay/xr871d.log", &st) == 0 && st.st_size > 16384)
		unlink("/overlay/xr871d.log");
	f = fopen("/overlay/xr871d.log", "a");
	if (!f)
		return;
	t = time(NULL);
	fprintf(f, "boot ok: up %lds reply@%ldms hb=%lu rx=%lu bad=%lu clock=%s %s",
		now_ms() / 1000, first_reply_ms, n_tx_hb, n_rx, n_rx_bad,
		clock_set ? "xr871" : "unset", ctime(&t));
	fclose(f);
	sync();
	boot_logged = 1;
}

static const char *wake_name(uint32_t r)
{
	switch (r) {
	case 0x004: return "cold";
	case 0x101: return "pir";
	case 0x102: return "key";
	case 0x103: return "wlan";
	case 0x104: return "timer";
	default: return NULL;
	}
}

/* /run is a tmpfs mounted by "mount -a" after we start: wait for it */
static void write_wake(void)
{
	struct stat st;
	const char *n;
	FILE *f;

	if (!wake_pending_write || stat("/run/lock", &st) != 0)
		return;
	f = fopen("/run/xr871d.wake", "w");
	if (!f)
		return;
	n = wake_name(wake_reason);
	if (n)
		fprintf(f, "%s\n", n);
	else
		fprintf(f, "0x%08x\n", (unsigned)wake_reason);
	fclose(f);
	wake_pending_write = 0;
}

static socklen_t ctl_addr(struct sockaddr_un *a)
{
	/* XR871D_CTL: other socket name, for tests next to a real daemon */
	const char *name = getenv("XR871D_CTL");
	size_t n;

	if (!name || !*name)
		name = "xr871d";
	n = strlen(name);
	if (n > sizeof(a->sun_path) - 2)
		n = sizeof(a->sun_path) - 2;
	memset(a, 0, sizeof(*a));
	a->sun_family = AF_UNIX;
	memcpy(a->sun_path + 1, name, n);	/* abstract */
	return offsetof(struct sockaddr_un, sun_path) + 1 + n;
}

/*
 * Client side of "-c": the request goes to the daemon's abstract socket
 * from an auto-bound one, so the daemon can answer. Answers are text
 * datagrams; the last one is "\x04<rc>". The daemon keeps sending progress
 * during long commands, so the client only gives up after 60 s of silence.
 */
static int ctl_client(const char *cmd)
{
	struct sockaddr_un a;
	socklen_t l = ctl_addr(&a);
	sa_family_t fam = AF_UNIX;
	char req[512], rbuf[1024];
	int s = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);

	/* fwupdate: the daemon runs in /, make the file name absolute */
	if (!strncmp(cmd, "fwupdate ", 9) && cmd[9] && cmd[9] != '/' && cmd[9] != '-') {
		char cwd[256];

		if (!getcwd(cwd, sizeof(cwd)))
			cwd[0] = 0;
		snprintf(req, sizeof(req), "fwupdate %s/%s", cwd, cmd + 9);
	} else {
		snprintf(req, sizeof(req), "%s", cmd);
	}
	if (s < 0 || bind(s, (struct sockaddr *)&fam, sizeof(fam)) < 0 ||
	    sendto(s, req, strlen(req), 0, (struct sockaddr *)&a, l) < 0) {
		fprintf(stderr, "xr871d: not running? %s\n", strerror(errno));
		return 1;
	}
	for (;;) {
		fd_set rf;
		struct timeval tv = { 60, 0 };
		ssize_t n;

		FD_ZERO(&rf);
		FD_SET(s, &rf);
		if (select(s + 1, &rf, NULL, NULL, &tv) <= 0) {
			fprintf(stderr, "xr871d: no answer from the daemon\n");
			return 1;
		}
		n = recv(s, rbuf, sizeof(rbuf) - 1, 0);
		if (n <= 0)
			return 1;
		rbuf[n] = 0;
		if (rbuf[0] == 4)
			return atoi(rbuf + 1);
		printf("%s\n", rbuf);
		fflush(stdout);
	}
}

/* daemon side: answer the client of the request being processed */
static struct sockaddr_un cli;
static socklen_t cli_len;

/* A unix datagram queue holds only net.unix.max_dgram_qlen (10 on the
 * camera) messages: a long reply (status) overran it and the rest, end
 * marker included, was dropped. Retry briefly instead; bounded so the
 * heartbeat (<= 3 s) is never at risk. */
static void ctl_send(const char *b, int n)
{
	int i;

	if (ctl < 0 || cli_len <= sizeof(sa_family_t))
		return;
	for (i = 0; i < 20; i++) {
		if (sendto(ctl, b, n, MSG_DONTWAIT, (struct sockaddr *)&cli, cli_len) >= 0 ||
		    (errno != EAGAIN && errno != EWOULDBLOCK))
			return;
		usleep(10000);
	}
}

static void out(const char *fmt, ...)
{
	char b[512];
	va_list ap;
	int n;

	va_start(ap, fmt);
	n = vsnprintf(b, sizeof(b), fmt, ap);
	va_end(ap);
	if (n < 0)
		return;
	if (n >= (int)sizeof(b))
		n = sizeof(b) - 1;
	if (verbose)
		fprintf(stderr, "xr871d> %s\n", b);
	ctl_send(b, n);
}

static void out_end(int rc)
{
	char b[8];
	int n = snprintf(b, sizeof(b), "\x04%d", rc);

	ctl_send(b, n);
}

static void ctl_open(void)
{
	struct sockaddr_un a;
	socklen_t l = ctl_addr(&a);

	ctl = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (ctl >= 0 && bind(ctl, (struct sockaddr *)&a, l) < 0) {
		logk("control socket: %s", strerror(errno));
		close(ctl);
		ctl = -1;
	}
}

static int ext_command(char *c);

static void ctl_input(void)
{
	char c[512];
	ssize_t n;
	unsigned long secs = 0;
	uint8_t p[4];
	int rc = 0;

	cli_len = sizeof(cli);
	n = recvfrom(ctl, c, sizeof(c) - 1, 0, (struct sockaddr *)&cli, &cli_len);
	if (n <= 0)
		return;
	c[n] = 0;
	if (ext_command(c) >= 0)
		return;		/* handled and answered there */
	if (!strncmp(c, "sleep", 5)) {
		secs = strtoul(c + 5, NULL, 0);
		logk("sleep requested (wake timer %lu s)", secs);
		sync();
		p[0] = secs; p[1] = secs >> 8; p[2] = secs >> 16; p[3] = secs >> 24;
		send_frame(0x83, 0, p, 4);
	} else if (!strcmp(c, "wifi")) {
		send_wifi();
	} else if (!strncmp(c, "ap ", 3)) {
		send_ap(c + 3);
	} else if (!strcmp(c, "sta")) {
		unlink(WIFI_OP_FILE);
		send_frame(0xc7, 0, NULL, 0);
	} else if (!strcmp(c, "scan")) {
		unlink(WIFI_OP_FILE);
		send_frame(0xc8, 0, NULL, 0);
	} else if (!strcmp(c, "probe")) {
		probe_ready();
	} else if (!strcmp(c, "led blue 1") || !strcmp(c, "led blue 0")) {
		/* blue status LED (bridge firmware ap24+; older ones ignore it) */
		send_frame(0xd5, c[9] == '1', NULL, 0);
	} else if (!strcmp(c, "stay")) {
		logk("sleep withdrawn");
		send_frame(0x83, 1, NULL, 0);
	} else {
		logk("unknown control command '%s'", c);
		out("unknown command '%s' (status, mcu, gpio, fwupdate, sleep, stay, wifi, probe, ap, sta, scan, led)", c);
		rc = 2;
	}
	if (!rc)
		out("ok");
	out_end(rc);
	cli_len = 0;
}

/* ---- bridge firmware extras ---------------------------------------- */

/*
 * WiFi setup support (captive portal, see S38xr871portal):
 *   xr871d -c 'ap <ssid> [psk]'  XR871 becomes an access point
 *   xr871d -c sta                back to station mode
 *   xr871d -c scan               scan (station mode only)
 * Results: WIFI_OP_FILE = "<op> <ok|error>" (op: sta, ap, scan) when the
 * XR871 is done, WIFI_MODE_FILE = "ap" / "sta", SCAN_FILE = the scan in
 * `wpa_cli scan_results` format (so Thingino's portal can read it).
 */

static void write_str(const char *path, const char *s)
{
	char tmp[64];
	FILE *f;

	snprintf(tmp, sizeof(tmp), "%s.new", path);
	f = fopen(tmp, "w");
	if (!f)
		return;
	fputs(s, f);
	fclose(f);
	rename(tmp, path);
}

static void scan_entry(uint16_t idx, const uint8_t *e, int len)
{
	static const char *flags[] = { "[ESS]", "[WEP][ESS]", "[WPA-PSK-CCMP+TKIP][ESS]",
		"[WPA2-PSK-CCMP][ESS]", "[WPA-PSK-CCMP+TKIP][WPA2-PSK-CCMP][ESS]" };
	FILE *f = fopen(SCAN_TMP, idx ? "a" : "w");
	int sl = e[9], i;

	if (!f)
		return;
	if (!idx)
		fputs("bssid / frequency / signal level / flags / ssid\n", f);
	if (sl > len - 10)
		sl = len - 10;
	fprintf(f, "%02x:%02x:%02x:%02x:%02x:%02x\t%d\t%d\t%s\t",
		e[0], e[1], e[2], e[3], e[4], e[5],
		e[7] >= 1 && e[7] <= 13 ? 2407 + 5 * e[7] : e[7] == 14 ? 2484 : 0,
		(int8_t)e[6], flags[e[8] < 5 ? e[8] : 0]);
	for (i = 0; i < sl; i++)	/* keep one network per line */
		fputc(e[10 + i] == '\n' || e[10 + i] == '\t' ? ' ' : e[10 + i], f);
	fputc('\n', f);
	fclose(f);
}

static void wifi_op_done(uint16_t param)
{
	static const char *names[] = { "sta", "ap", "scan" };
	int op = param & 0xff, ok = !(param >> 8);
	char s[32];

	if (op > 2)
		return;
	if (op == 2) {
		if (ok)
			rename(SCAN_TMP, SCAN_FILE);
		else
			unlink(SCAN_TMP);
	} else if (ok) {
		write_str(WIFI_MODE_FILE, op == 1 ? "ap\n" : "sta\n");
	}
	snprintf(s, sizeof(s), "%s %s\n", names[op], ok ? "ok" : "error");
	write_str(WIFI_OP_FILE, s);
	logk("XR871: wifi %s %s", names[op], ok ? "done" : "FAILED");
}

/* cmd 0xc6: same layout as 0xc0, psk_len 0 = open AP */
static void send_ap(const char *arg)
{
	uint8_t p[1 + 32 + 1 + 64];
	const char *sp = strchr(arg, ' ');
	size_t sl = sp ? (size_t)(sp - arg) : strlen(arg), pl = sp ? strlen(sp + 1) : 0;

	if (!sl || sl > 32 || pl > 64 || (pl && pl < 8)) {
		logk("ap: bad ssid/psk length");
		return;
	}
	memset(p, 0, sizeof(p));
	p[0] = sl;
	memcpy(p + 1, arg, sl);
	p[33] = pl;
	if (pl)
		memcpy(p + 34, sp + 1, pl);
	unlink(WIFI_OP_FILE);
	send_frame(0xc6, 0, p, sizeof(p));
	memset(p, 0, sizeof(p));
	logk("ap requested (ssid %u bytes, %s)", (unsigned)sl, pl ? "WPA2" : "open");
}

static void unquote(char *v, char *out, size_t n)
{
	size_t l;

	while (*v == ' ' || *v == '\t')
		v++;
	l = strcspn(v, "\r\n");
	v[l] = 0;
	if (*v == '"') {
		v++;
		l = strcspn(v, "\"");
	}
	if (l >= n)
		l = n - 1;
	memcpy(out, v, l);
	out[l] = 0;
}

/* cmd 0xc0: u8 ssid_len, ssid[32], u8 psk_len, psk[64]; never logged */
static void send_wifi(void)
{
	char line[160], ssid[33] = "", psk[65] = "";
	uint8_t p[1 + 32 + 1 + 64];
	FILE *f = fopen("/etc/wpa_supplicant.conf", "r");
	int in_net = 0;

	if (!f) {
		logk("no /etc/wpa_supplicant.conf, WiFi not configured");
		return;
	}
	while (fgets(line, sizeof(line), f)) {
		char *k = line;

		while (*k == ' ' || *k == '\t')
			k++;
		if (!strncmp(k, "network={", 9))
			in_net++;
		if (in_net != 1)
			continue;
		if (!strncmp(k, "ssid=", 5))
			unquote(k + 5, ssid, sizeof(ssid));
		else if (!strncmp(k, "psk=", 4))
			unquote(k + 4, psk, sizeof(psk));
	}
	fclose(f);
	if (!ssid[0] || strlen(psk) < 8) {
		logk("wpa_supplicant.conf has no usable ssid/psk");
		return;
	}
	memset(p, 0, sizeof(p));
	p[0] = strlen(ssid);
	memcpy(p + 1, ssid, p[0]);
	p[33] = strlen(psk);
	memcpy(p + 34, psk, p[33]);
	send_frame(0xc0, 0, p, sizeof(p));
	memset(p, 0, sizeof(p));
	memset(psk, 0, sizeof(psk));
	logk("WiFi credentials sent to the XR871 (ssid %u bytes)", (unsigned)strlen(ssid));
}

static int conf_get(const char *key)
{
	char line[64];
	size_t kl = strlen(key);
	int v = -1;
	FILE *f = fopen(CONF, "r");

	if (!f)
		return -1;
	while (fgets(line, sizeof(line), f))
		if (!strncmp(line, key, kl) && line[kl] == '=')
			v = atoi(line + kl + 1);
	fclose(f);
	return v;
}

/* bad pins are kept as bad_N=1 lines; probing marks probing=N first */
static void conf_write(int ready, int probing, int new_bad)
{
	char line[64], keep[512] = "";
	FILE *f = fopen(CONF, "r");

	if (f) {
		while (fgets(line, sizeof(line), f))
			if (!strncmp(line, "bad_", 4) && strlen(keep) + strlen(line) < sizeof(keep))
				strcat(keep, line);
		fclose(f);
	}
	f = fopen(CONF ".tmp", "w");
	if (!f)
		return;
	fputs(keep, f);
	if (new_bad >= 0)
		fprintf(f, "bad_%d=1\n", new_bad);
	if (ready >= 0)
		fprintf(f, "ready_pin=%d\n", ready);
	if (probing >= 0)
		fprintf(f, "probing=%d\n", probing);
	fclose(f);
	rename(CONF ".tmp", CONF);
	sync();
}

static int gpio77(void)
{
	char p[48], c = 0;
	int f;

	snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/value", READY_GPIO);
	if (access(p, F_OK) != 0) {
		f = open("/sys/class/gpio/export", O_WRONLY);
		if (f >= 0) {
			if (write(f, "77", 2) < 0) { /* already exported */ }
			close(f);
		}
	}
	f = open(p, O_RDONLY);
	if (f < 0)
		return -1;
	if (read(f, &c, 1) != 1)
		c = 0;
	close(f);
	return c == '1';
}

static void heartbeat_tick(void)
{
	long now = now_ms();

	if (now >= next_hb) {
		send_frame(0xa9, 0, NULL, 0);
		n_tx_hb++;
		next_hb = now + HEARTBEAT_MS;
	}
}

static void drain(int ms)
{
	long end = now_ms() + ms;
	uint8_t in[256];

	while (now_ms() < end) {
		fd_set rf;
		struct timeval tv = { 0, 5000 };

		FD_ZERO(&rf);
		FD_SET(fd, &rf);
		if (select(fd + 1, &rf, NULL, NULL, &tv) > 0) {
			ssize_t n = read(fd, in, sizeof(in));
			if (n > 0)
				parse(in, n);
		}
	}
}

/* most likely first: PA15 is the stock "busy/ready" pair member */
static const int candidates[] = { 15, 14, 13, 11, 10, 6 };

static void probe_ready(void)
{
	unsigned i;
	int found = -1;
	char key[16];

	if (gpio77() < 0) {
		logk("probe: GPIO %d not available", READY_GPIO);
		return;
	}
	for (i = 0; i < sizeof(candidates) / sizeof(candidates[0]); i++) {
		int pin = candidates[i], hi, lo;

		snprintf(key, sizeof(key), "bad_%d", pin);
		if (conf_get(key) == 1)
			continue;
		conf_write(-1, pin, -1);	/* survives a T30 reset */
		send_frame(0xc4, pin | 1 << 8, NULL, 0);
		drain(60);
		hi = gpio77();
		send_frame(0xc4, pin, NULL, 0);
		drain(60);
		lo = gpio77();
		heartbeat_tick();	/* keep the heartbeat going */
		if (hi == 1 && lo == 0) {
			found = pin;
			break;
		}
	}
	conf_write(found, -1, -1);
	if (found >= 0) {
		ready_pin = found;
		logk("probe: SPI ready line is XR871 PA%d", found);
		send_frame(0xc5, found, NULL, 0);
	} else {
		logk("probe: no XR871 pin drives GPIO %d", READY_GPIO);
	}
}

/* once per boot, when the bridge firmware is known */
static void bridge_setup(void)
{
	static int done;
	int probing;

	if (done || !bridge_fw)
		return;
	done = 1;
	send_wifi();
	probing = conf_get("probing");
	if (probing >= 0) {
		/* the last boot died while this pin was raised */
		logk("probe: PA%d reset the T30 last time, marked bad", probing);
		conf_write(-1, -1, probing);
	}
	ready_pin = conf_get("ready_pin");
	if (ready_pin >= 0)
		send_frame(0xc5, ready_pin, NULL, 0);
	else
		probe_ready();
}

static void on_sig(int s)
{
	if (s == SIGUSR1)
		want_power = 0;
	else if (s == SIGUSR2)
		want_power = 1;
	else
		stop = 1;
}

static void usage(void)
{
	fprintf(stderr, "usage: xr871d [-b] [-v] [-d /dev/ttyS0] [-l file] | -c '<command>'\n"
		"  -b  run in background\n  -v  verbose\n"
		"  -l  write XR871 log lines to <file> instead of syslog\n"
		"  -c  send a command to the running daemon:\n"
		"      status | mcu <cmd> <val> [force] | gpio <PAn> <0|1|in|blink|off> [s]\n"
		"      gpio scan [s] PAn [PAn ...] | fwupdate <file> [--commit] [--reboot]\n"
		"      [--force-stage] | fwupdate --info|--abort|--commit\n"
		"      sleep [s] | stay | wifi | probe | ap <ssid> [psk] | sta | scan\n");
}

int main(int argc, char **argv)
{
	long next_hello, last_rx = 0;
	struct stat st_dummy;
	struct sigaction sa;
	int bg = 0, c;

	while ((c = getopt(argc, argv, "bvd:c:l:h")) != -1) {
		switch (c) {
		case 'c': return ctl_client(optarg);
		case 'b': bg = 1; break;
		case 'v': verbose = 1; break;
		case 'd': dev = optarg; break;
		case 'l': xlog_file = optarg; break;
		default: usage(); return 1;
		}
	}

	if (bg) {
		pid_t p = fork();
		if (p < 0)
			return 1;
		if (p > 0)
			return 0;
		setsid();
		if (chdir("/") < 0) { /* ignore */ }
	}

	memset(&sa, 0, sizeof(sa));
	sa.sa_handler = on_sig;
	sigaction(SIGUSR1, &sa, NULL);
	sigaction(SIGUSR2, &sa, NULL);
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	signal(SIGPIPE, SIG_IGN);

	/* the device node may appear a moment after early init */
	for (c = 0; c < 50 && (fd = uart_open()) < 0; c++)
		usleep(20000);
	if (fd < 0) {
		logk("cannot open %s: %s", dev, strerror(errno));
		return 1;
	}
	logk("started v" VERSION " on %s", dev);
	ctl_open();

	/* heartbeat right away: the XR871 timer is already running */
	send_frame(0xa9, 0, NULL, 0);
	n_tx_hb++;
	send_frame(0x00, 0, NULL, 0);
	next_hb = now_ms() + HEARTBEAT_MS;
	next_hello = now_ms() + HELLO_MS;

	while (!stop) {
		fd_set rf;
		struct timeval tv;
		long now = now_ms();
		long wait = next_hb - now;
		uint8_t in[256];
		int r;

		if (first_reply_ms < 0 && next_hello - now < wait)
			wait = next_hello - now;
		if (wait < 0)
			wait = 0;
		if (wait > 1000)
			wait = 1000;	/* poll overlay for the boot record */
		if (pending_short() && wait > 25)
			wait = 25;	/* finish a stock 8-byte frame quickly */

		FD_ZERO(&rf);
		FD_SET(fd, &rf);
		if (ctl >= 0)
			FD_SET(ctl, &rf);
		tv.tv_sec = wait / 1000;
		tv.tv_usec = (wait % 1000) * 1000;
		r = select((ctl > fd ? ctl : fd) + 1, &rf, NULL, NULL, &tv);
		if (r > 0 && FD_ISSET(fd, &rf)) {
			ssize_t n = read(fd, in, sizeof(in));
			if (n > 0) {
				parse(in, n);
				last_rx = now_ms();
			}
		} else if (now_ms() - last_rx > 20) {
			parse_flush();	/* line idle: a stock 8-byte frame is complete */
		}
		if (r > 0 && ctl >= 0 && FD_ISSET(ctl, &rf))
			ctl_input();

		if (want_power >= 0) {
			logk("requesting power state %d", (int)want_power);
			send_frame(0x83, want_power, NULL, 0);
			want_power = -1;
		}

		heartbeat_tick();
		now = now_ms();
		if (first_reply_ms < 0 && now >= next_hello) {
			send_frame(0x00, 0, NULL, 0);
			next_hello = now + HELLO_MS;
		}
		boot_record();
		write_wake();
		{
			static long long next_standby;

			if (!next_standby)
				next_standby = now + STANDBY_TICK_MS;
			else if (now >= next_standby && stat("/run/lock", &st_dummy) == 0) {
				next_standby = now + STANDBY_TICK_MS;
				run_hook(STANDBY_HOOK, "tick");
			}
		}
		if (stat("/run/lock", &st_dummy) == 0) {	/* /etc overlay + /sys ready */
			static time_t wpa_mtime;

			bridge_setup();
			/* WebUI / "wlan configure" rewrote the credentials */
			if (bridge_fw && stat("/etc/wpa_supplicant.conf", &st_dummy) == 0) {
				if (wpa_mtime && st_dummy.st_mtime != wpa_mtime)
					send_wifi();
				wpa_mtime = st_dummy.st_mtime;
			}
		}
	}

	logk("stopping");
	close(fd);
	return 0;
}

#include "xr871d_ext.c"

