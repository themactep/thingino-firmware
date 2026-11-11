/*
 * pir_daemon: decode ATBM6441 uartmsg frames on /dev/ttyS0 and surface
 * PIR trigger, battery, and WiFi status on the video OSD via raptor's
 * rod daemon.
 *
 * Frame: 0x7B(start) LEN TYPE PAYLOAD[LEN-4] CHECKSUM
 *   LEN counts the whole frame (start..checksum), valid range 4..132.
 *   CHECKSUM = (~(start ^ LEN ^ TYPE ^ payload bytes)) & 0xFF
 *
 * Reverse-engineered from the vendor's contractMCU uartmsg code and
 * confirmed against live hardware:
 *   - PIR wave -> unsolicited `7B 04 03 83` (TYPE=0x03, no payload),
 *     repeated for the duration of motion.
 *   - Battery -> we send getPowerInfo `7B 04 45 C5` (TYPE=0x45, no
 *     payload); MCU replies TYPE=0x45 with 12 payload bytes. Layout
 *     (from contractMCU's getPowerInfo handler, live-verified):
 *       [0] powerOnType  [1] capacity %  [2] chargingStatus
 *       [3] pad          [4..5] voltage mV (little-endian)  [6..] extra
 *   - USB charge -> unsolicited zero-payload events: TYPE=0x04 charger
 *     connected, TYPE=0x05 charger disconnected (live-verified; the
 *     SYSTEM_IN/OUT_CHARGE events seen in jooanipc). These flip the
 *     charging indicator immediately, ahead of the 30s battery poll.
 *
 * WiFi RSSI is polled from the SDIO driver via ioctl(ATBM_RSSI) on
 * /dev/atbm_ioctl -- the same call atbm_iot_cli's get_rssi makes;
 * opening it alongside the running supplicant is fine.
 *
 * OSD (rod control socket, 2-byte BE length + JSON): one element
 *   "status" -> "WiFi %wifi%  BAT %batt%  PIR %pir%"   (bottom_left)
 * so PIR sits beside the WiFi and battery readouts. The element is
 * re-registered before every update so a rod restart can't orphan the
 * display (re-add of an existing element is a cheap no-op error we
 * ignore).
 *
 * NOTE: deliberately does NOT talk to rmd -- enabling rmd/IVS hard-locks
 * this board (see session log 2026-07-07); OSD-only until that is fixed.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <time.h>
#include <stdint.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/un.h>

#define MAX_FRAME 132
#define ROD_SOCK_PATH "/var/run/rss/rod.sock"

#define PIR_TYPE 0x03
#define CHG_IN_TYPE 0x04  /* USB charger connected (SYSTEM_IN_CHARGE)    */
#define CHG_OUT_TYPE 0x05 /* USB charger disconnected (SYSTEM_OUT_CHARGE) */
#define PWR_TYPE 0x45
#define PIR_HOLD_SEC 5
#define BATT_POLL_SEC 30
#define RSSI_POLL_SEC 10

/* getPowerInfo request: 7B 04 45 C5 (empty payload, chk = ~(7B^04^45)) */
static const unsigned char PWR_QUERY[4] = {0x7B, 0x04, PWR_TYPE, 0xC5};

/* SDIO driver RSSI ioctl (atbm_ioctl_ext.h: _IOR(121, 34, uint)) */
#define ATBM_DEV "/dev/atbm_ioctl"
#define ATBM_IOCTL 121
#define ATBM_RSSI _IOR(ATBM_IOCTL, 34, unsigned int)
struct rssi_info {
	uint32_t status;
	int rssi;
};

static int open_uart(const char *path)
{
	int fd = open(path, O_RDWR | O_NOCTTY);
	if (fd < 0) {
		perror("open");
		return -1;
	}

	struct termios tio;
	if (tcgetattr(fd, &tio) != 0) {
		perror("tcgetattr");
		close(fd);
		return -1;
	}

	cfmakeraw(&tio);
	cfsetispeed(&tio, B115200);
	cfsetospeed(&tio, B115200);
	tio.c_cflag |= (CLOCAL | CREAD);
	tio.c_cflag &= ~PARENB;
	tio.c_cflag &= ~CSTOPB;
	tio.c_cflag &= ~CSIZE;
	tio.c_cflag |= CS8;
	tio.c_cc[VMIN] = 1;
	tio.c_cc[VTIME] = 0;

	if (tcsetattr(fd, TCSANOW, &tio) != 0) {
		perror("tcsetattr");
		close(fd);
		return -1;
	}

	return fd;
}

static void timestamp(char *buf, size_t len)
{
	struct timespec ts;
	clock_gettime(CLOCK_REALTIME, &ts);
	struct tm tm;
	localtime_r(&ts.tv_sec, &tm);
	snprintf(buf, len, "%02d:%02d:%02d.%03ld",
		 tm.tm_hour, tm.tm_min, tm.tm_sec, ts.tv_nsec / 1000000);
}

/* Send one JSON command to rod's control socket and drain the response.
 * Best-effort: if rod isn't up yet, fail silently. Returns 0 on success. */
static int rod_send(const char *json)
{
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	if (fd < 0)
		return -1;

	struct sockaddr_un addr = {0};
	addr.sun_family = AF_UNIX;
	strncpy(addr.sun_path, ROD_SOCK_PATH, sizeof(addr.sun_path) - 1);

	struct timeval tv = {.tv_sec = 1, .tv_usec = 0};
	setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

	if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
		close(fd);
		return -1;
	}

	uint16_t len = (uint16_t)strlen(json);
	unsigned char hdr[2] = {(unsigned char)(len >> 8), (unsigned char)(len & 0xFF)};

	if (write(fd, hdr, 2) != 2 || write(fd, json, len) != (ssize_t)len) {
		close(fd);
		return -1;
	}

	/* Drain the response so rod's accept/handle loop doesn't stall. */
	unsigned char resp_hdr[2];
	if (read(fd, resp_hdr, 2) == 2) {
		uint16_t resp_len = ((uint16_t)resp_hdr[0] << 8) | resp_hdr[1];
		char discard[256];
		while (resp_len > 0) {
			size_t chunk = resp_len > sizeof(discard) ? sizeof(discard) : resp_len;
			ssize_t n = read(fd, discard, chunk);
			if (n <= 0)
				break;
			resp_len -= (uint16_t)n;
		}
	}

	close(fd);
	return 0;
}

/* add-element (idempotent) for the given name, then set its variable.
 * Returns 0 if rod accepted the set-var. */
static int osd_set(const char *add_json, const char *var, const char *value)
{
	rod_send(add_json);

	char cmd[160];
	snprintf(cmd, sizeof(cmd), "{\"cmd\":\"set-var\",\"name\":\"%s\",\"value\":\"%s\"}",
		 var, value);
	if (rod_send(cmd) != 0) {
		char ts[32];
		timestamp(ts, sizeof(ts));
		fprintf(stderr, "[%s] rod not reachable at %s (will retry)\n", ts, ROD_SOCK_PATH);
		return -1;
	}
	return 0;
}

/* Single status line carrying all three fields so PIR sits beside the
 * WiFi and battery readouts. Each set-var below feeds this one element. */
#define STATUS_ELEM \
	"{\"cmd\":\"add-element\",\"name\":\"status\",\"type\":\"text\"," \
	"\"template\":\"WiFi %wifi%  BAT %batt%  PIR %pir%\"," \
	"\"position\":\"bottom_left\",\"max_chars\":40}"

static int osd_set_pir(const char *value)
{
	return osd_set(STATUS_ELEM, "pir", value);
}

static int osd_set_wifi(const char *value)
{
	return osd_set(STATUS_ELEM, "wifi", value);
}

static int osd_set_batt(const char *value)
{
	return osd_set(STATUS_ELEM, "batt", value);
}

/* Poll the SDIO driver for the AP RSSI. Open per call so a driver
 * reload can't strand a stale fd. Sets "-61dBm" or "off". */
static void poll_rssi(char *out, size_t out_len)
{
	struct rssi_info info = {0};
	int fd = open(ATBM_DEV, O_RDWR);
	if (fd < 0) {
		snprintf(out, out_len, "off");
		return;
	}
	int ret = ioctl(fd, ATBM_RSSI, &info);
	close(fd);
	if (ret != 0 || info.rssi >= 0 || info.rssi < -120)
		snprintf(out, out_len, "off");
	else
		snprintf(out, out_len, "%ddBm", info.rssi);
}

/* Shared battery state. capacity -1 = unknown; charging updated by both
 * the periodic getPowerInfo reply and the real-time USB charge events. */
static int batt_cap = -1;
static int batt_charging = 0;

/* Repaint the "batt" OSD var from current state: "84%", "84%+" charging,
 * or "--" when capacity is still unknown. */
static void refresh_batt(void)
{
	char bt[16];
	if (batt_cap < 0)
		snprintf(bt, sizeof(bt), "--");
	else
		snprintf(bt, sizeof(bt), "%d%%%s", batt_cap, batt_charging ? "+" : "");
	osd_set_batt(bt);
}

/* Update state from a TYPE=0x45 getPowerInfo reply (paylen >= 6):
 * [1]=capacity%, [2]=chargingStatus, [4..5]=voltage mV LE. */
static int decode_battery(const unsigned char *payload, int paylen)
{
	if (paylen < 6)
		return -1;
	int cap = payload[1];
	if (cap < 0 || cap > 100)
		return -1;
	batt_cap = cap;
	batt_charging = payload[2] ? 1 : 0;
	return 0;
}

int main(int argc, char *argv[])
{
	const char *dev = (argc > 1) ? argv[1] : "/dev/ttyS0";
	int fd = open_uart(dev);
	if (fd < 0)
		return 1;

	printf("pir_daemon: %s -> rod OSD (pir/wifi/batt)\n", dev);
	fflush(stdout);

	unsigned char buf[MAX_FRAME];
	int have = 0;
	time_t last_trigger = 0;
	int motion_shown = 0;

	/* rod may still be initializing when we start (S32 vs S31raptor);
	 * retry the initial paint on the idle tick until it lands. */
	int synced = 0;
	synced = (osd_set_pir("--") == 0);
	osd_set_wifi("off");
	osd_set_batt("--");

	time_t last_batt = 0;   /* force an immediate battery query + rssi */
	time_t last_rssi = 0;

	for (;;) {
		fd_set rfds;
		FD_ZERO(&rfds);
		FD_SET(fd, &rfds);
		struct timeval tv = {.tv_sec = 0, .tv_usec = 500000};

		int sr = select(fd + 1, &rfds, NULL, NULL, &tv);
		if (sr < 0) {
			perror("select");
			break;
		}

		time_t now = time(NULL);

		/* Periodic WiFi RSSI poll */
		if (now - last_rssi >= RSSI_POLL_SEC) {
			char w[24];
			poll_rssi(w, sizeof(w));
			osd_set_wifi(w);
			last_rssi = now;
		}

		/* Periodic battery query: transmit getPowerInfo; the TYPE=0x45
		 * reply is decoded asynchronously in the frame handler below. */
		if (now - last_batt >= BATT_POLL_SEC) {
			if (write(fd, PWR_QUERY, sizeof(PWR_QUERY)) != (ssize_t)sizeof(PWR_QUERY))
				perror("battery query write");
			last_batt = now;
		}

		if (sr == 0) {
			/* idle tick: expire the MOTION display, retry paint */
			if (motion_shown && now - last_trigger >= PIR_HOLD_SEC) {
				synced = (osd_set_pir("--") == 0);
				motion_shown = 0;
			} else if (!synced) {
				synced = (osd_set_pir(motion_shown ? "MOTION" : "--") == 0);
			}
			continue;
		}

		unsigned char b;
		ssize_t n = read(fd, &b, 1);
		if (n <= 0) {
			if (n < 0)
				perror("read");
			break;
		}

		if (have == 0) {
			if (b != 0x7B)
				continue;
			buf[have++] = b;
			continue;
		}

		buf[have++] = b;

		if (have == 2) {
			unsigned char len = buf[1];
			if (len < 4 || len > MAX_FRAME) {
				if (buf[1] == 0x7B) {
					buf[0] = buf[1];
					have = 1;
				} else {
					have = 0;
				}
			}
			continue;
		}

		unsigned char len = buf[1];
		if (have < len)
			continue;

		unsigned char chk = 0;
		int i;
		for (i = 0; i < len - 1; i++)
			chk ^= buf[i];
		chk = (~chk) & 0xFF;

		if (chk == buf[len - 1]) {
			unsigned char type = buf[2];
			int paylen = len - 4;
			const unsigned char *payload = &buf[3];

			if (type == PIR_TYPE && paylen == 0) {
				char ts[32];
				timestamp(ts, sizeof(ts));
				printf("[%s] PIR_TRIGGER -> OSD\n", ts);
				fflush(stdout);
				last_trigger = time(NULL);
				if (!motion_shown) {
					synced = (osd_set_pir("MOTION") == 0);
					motion_shown = 1;
				}
			} else if (type == PWR_TYPE) {
				if (decode_battery(payload, paylen) == 0) {
					char ts[32];
					timestamp(ts, sizeof(ts));
					printf("[%s] BATTERY %d%% charging=%d -> OSD\n",
					       ts, batt_cap, batt_charging);
					fflush(stdout);
					refresh_batt();
				}
			} else if (type == CHG_IN_TYPE || type == CHG_OUT_TYPE) {
				batt_charging = (type == CHG_IN_TYPE) ? 1 : 0;
				char ts[32];
				timestamp(ts, sizeof(ts));
				printf("[%s] USB %s -> OSD\n", ts,
				       batt_charging ? "CONNECTED" : "DISCONNECTED");
				fflush(stdout);
				refresh_batt();
			}
		}
		/* Unknown types / checksum errors: ignore, keep listening. */

		have = 0;
	}

	close(fd);
	return 0;
}
