/*
 * xr871d service extensions (included at the end of xr871d.c, one
 * translation unit): status, MCU passthrough, GPIO test, XR871 log /
 * MCU event forwarding, XR871 application update. Protocol: see
 * xr871fw/core/bridge_core.h and fw_update.h; everything here is only
 * sent to the bridge firmware (it answered our 0xf1 marker).
 */

#define EXT_TIMEOUT_MS 1500

/* last extension reply, filled by handle_ext() */
static struct {
	int want, got;
	uint16_t param, plen;
	uint8_t p[MAX_RX_PAYLOAD];
} rep = { -1, 0, 0, 0, { 0 } };
static int mcu_collect;		/* print MCU events to the -c caller */
static unsigned long n_xlog, n_mcu_ev;

static uint32_t rd32(const uint8_t *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

static void wr32(uint8_t *p, uint32_t v)
{
	p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24;
}

static int has_secret_word(const char *s)
{
	static const char *const w[] = { "psk", "passw", "passphr", "pmk", "secret" };
	char l[256];
	size_t i;

	for (i = 0; s[i] && i < sizeof(l) - 1; i++)
		l[i] = (s[i] >= 'A' && s[i] <= 'Z') ? s[i] + 32 : s[i];
	l[i] = 0;
	for (i = 0; i < sizeof(w) / sizeof(w[0]); i++)
		if (strstr(l, w[i]))
			return 1;
	return 0;
}

/* XR871 log line -> syslog "xr871" (kmsg until syslogd runs) */
static void xlog(const char *line)
{
	static int opened;
	struct stat st;

	if (has_secret_word(line))
		line = "[log line withheld: credential keyword]";
	n_xlog++;
	if (verbose)
		fprintf(stderr, "xr871: %s\n", line);
	if (xlog_file) {
		FILE *f = fopen(xlog_file, "a");

		if (f) {
			fprintf(f, "%s\n", line);
			fclose(f);
		}
		return;
	}
	if (stat("/dev/log", &st) == 0) {
		if (!opened) {
			openlog("xr871", LOG_NDELAY, LOG_DAEMON);
			opened = 1;
		}
		syslog(LOG_INFO, "%s", line);
	} else {
		char b[300];
		int k = open("/dev/kmsg", O_WRONLY | O_CLOEXEC), n;

		n = snprintf(b, sizeof(b), "<6>xr871: %s", line);
		if (k >= 0) {
			if (write(k, b, n > (int)sizeof(b) - 1 ? (int)sizeof(b) - 1 : n) < 0) { }
			close(k);
		}
	}
}

static void handle_ext(uint8_t cmd, uint16_t param, const uint8_t *p, uint16_t plen)
{
	if (cmd == 0xd4 && plen > 0) {		/* XR871 log line */
		char line[MAX_RX_PAYLOAD + 1];

		memcpy(line, p, plen);
		line[plen] = 0;
		xlog(line);
		return;
	}
	if (cmd == 0xd2) {			/* MCU event */
		n_mcu_ev++;
		/* the MCU heartbeat comes every few seconds: count it, but keep
		 * it out of the kernel log */
		if ((param & 0xff) != 0x0e || verbose)
			logk("mcu event {0x%02x,0x%02x}", param & 0xff, param >> 8);
		if (mcu_collect)
			out("mcu -> {0x%02x,0x%02x}", param & 0xff, param >> 8);
		return;
	}
	if (rep.want == cmd) {
		rep.param = param;
		rep.plen = plen > sizeof(rep.p) ? sizeof(rep.p) : plen;
		memcpy(rep.p, p, rep.plen);
		rep.got = 1;
	}
}

/* keep the link alive (heartbeat, frames) for ms; stop early once the
 * awaited reply is there */
static void pump(int ms)
{
	long end = now_ms() + ms, last = now_ms();
	uint8_t in[256];

	while (now_ms() < end && !(rep.want >= 0 && rep.got)) {
		fd_set rf;
		struct timeval tv = { 0, 10000 };

		heartbeat_tick();
		FD_ZERO(&rf);
		FD_SET(fd, &rf);
		if (select(fd + 1, &rf, NULL, NULL, &tv) > 0) {
			ssize_t n = read(fd, in, sizeof(in));

			if (n > 0) {
				parse(in, n);
				last = now_ms();
			}
		} else if (now_ms() - last > 20) {
			parse_flush();
		}
	}
}

/* send a request and wait for the reply with the same command; 0 = got it */
static int request(uint8_t cmd, uint16_t param, const void *p, size_t len, int timeout_ms)
{
	rep.want = cmd;
	rep.got = 0;
	send_frame(cmd, param, p, len);
	pump(timeout_ms);
	rep.want = -1;
	return rep.got ? 0 : -1;
}

static void ext_enable(void)
{
	rep.want = -1;
	/* XR871 log lines + MCU events; the stock T30 app never sends this,
	 * so the XR871 never sends those frames to it */
	send_frame(0xd4, 0x03, NULL, 0);
}

static int need_bridge(void)
{
	if (bridge_fw)
		return 0;
	out(first_reply_ms < 0 ? "XR871 does not answer" :
	    "XR871 runs the stock firmware: command not available");
	return -1;
}

/* ---- status ---------------------------------------------------------- */

static const char *const fwu_states[] = { "idle", "receiving", "received", "verified", "committed" };

static int cmd_status(void)
{
	static const char *const cn[] = {
		"t30 frames", "t30 bad", "t30 hb", "mcu rx", "mcu tx", "mcu tx err",
		"spi frames", "spi bad", "eth up", "eth down", "wifi drop",
		"log dropped", "sleeps", "wakes", "log lines", "mcu events"
	};
	const uint8_t *p = rep.p;
	const char *wn;
	char ver[65];
	uint32_t up, wr;
	unsigned i;

	if (need_bridge())
		return 1;
	if (request(0xd0, 0, NULL, 0, EXT_TIMEOUT_MS) || rep.plen < 88) {
		out("no status reply from the XR871 (firmware too old?)");
		return 1;
	}
	memset(ver, 0, sizeof(ver));
	if (rep.plen > 88)
		memcpy(ver, p + 88, rep.plen - 88 > 64 ? 64 : rep.plen - 88);
	up = rd32(p + 8);
	wr = rd32(p + 12);
	wn = wake_name(wr);
	out("xr871 firmware: %s", ver[0] ? ver : "?");
	out("mcu firmware:   %u", p[6]);
	out("xr871 uptime:   %lu s", (unsigned long)up / 1000);
	out("wake reason:    %s (0x%03x)", wn ? wn : "stock value", (unsigned)wr);
	if (!(p[1] & 0x04))
		out("battery:        unknown (fuel gauge not readable)");
	else if (p[2] == 0xff)
		out("battery:        ? %%, %u mV", p[4] | p[5] << 8);
	else if (p[4] | p[5] << 8)
		out("battery:        %u %%, %u mV", p[2], p[4] | p[5] << 8);
	else
		out("battery:        %u %%, voltage unknown", p[2]);
	if (p[84] & 4)
		out("usb power:      %s (MCU 0x1e/0x0c value 0x%02x)", p[82] ? "present" : "absent", p[82]);
	else
		out("usb power:      unknown (MCU did not report it yet)");
	if (rep.plen >= 160) {	/* battery tail, XR871 ap22+ */
		unsigned t2e = p[152] | p[153] << 8, chg = p[156] | p[157] << 8;

		/* the gauge's time to empty only means something on battery
		 * and below 100 % (it reads a fixed 1146 when full) */
		if (t2e != 0xffff && (p[84] & 4) && !p[82] && p[2] < 100)
			out("time to empty:  about %u h %02u min (gauge estimate)", t2e / 60, t2e % 60);
		if (chg)
			out("charge restart: %u x (SOC fell below 100 %% on USB)", chg);
		if (p[158] == 0xff)
			out("low battery:    shutdown sent to the MCU");
		else if (p[158])
			out("low battery:    %u low reading(s) in a row (shutdown at 3)", p[158]);
	}
	if (p[84] & 8)
		out("main battery:   event 0x2d val 0x%02x", p[83]);
	if (p[84] & 3)
		out("mcu state:      0x1e=0x%02x 0x1f=0x%02x", p[80], p[81]);
	if (!(p[1] & 0x01))
		out("wifi:           not in this firmware");
	else if (p[1] & 0x02)
		out("wifi:           associated, rssi %d dBm", (int8_t)p[3]);
	else
		out("wifi:           not associated");
	out("t30 power:      %s, forwarding mask 0x%02x", p[1] & 0x08 ? "on" : "off", p[87]);
	out("fw update:      %s, running image %s, OTA %s",
	    p[7] < 5 ? fwu_states[p[7]] : "?",
	    p[85] == 0xff ? "? (flash not probed; 'fwupdate --info')" : p[85] ? "2" : "1",
	    p[86] == 0xff ? "?" : p[86] ? "enabled" : "DISABLED in boot header");
	for (i = 0; i < 16; i += 4)
		out("%-11s %8lu   %-11s %8lu   %-11s %8lu   %-11s %8lu",
		    cn[i], (unsigned long)rd32(p + 16 + 4 * i),
		    cn[i + 1], (unsigned long)rd32(p + 20 + 4 * i),
		    cn[i + 2], (unsigned long)rd32(p + 24 + 4 * i),
		    cn[i + 3], (unsigned long)rd32(p + 28 + 4 * i));
	out("xr871d:         v" VERSION ", rx %lu bad %lu hb sent %lu, xr871 log lines %lu, mcu events %lu",
	    n_rx, n_rx_bad, n_tx_hb, n_xlog, n_mcu_ev);
	return 0;
}

/* ---- MCU passthrough ---------------------------------------------------- */

static int cmd_mcu(char *args)
{
	char *a = strtok(args, " "), *b = strtok(NULL, " "), *f = strtok(NULL, " ");
	unsigned long cmd, val;
	uint8_t flags = 0;
	char *e1, *e2;

	if (need_bridge())
		return 1;
	if (!a || !b) {
		out("usage: mcu <cmd> <val> [force]   (numbers, 0x.. allowed)");
		return 2;
	}
	cmd = strtoul(a, &e1, 0);
	val = strtoul(b, &e2, 0);
	if (*e1 || *e2 || cmd > 255 || val > 255) {
		out("mcu: cmd and val are bytes");
		return 2;
	}
	if (f && !strcmp(f, "force"))
		flags = 1;
	if (((cmd == 0x05 && val != 0x07) || cmd == 0x24) && !flags) {
		out("mcu: {0x%02lx,0x%02lx} can switch the T30 (this system) or the board off;"
		    " add 'force' if you really mean it", cmd, val);
		return 3;
	}
	mcu_collect = 1;
	if (request(0xd1, cmd | val << 8, &flags, 1, EXT_TIMEOUT_MS)) {
		mcu_collect = 0;
		out("mcu: no answer from the XR871");
		return 1;
	}
	if (rep.param == 0xfffe) {
		mcu_collect = 0;
		out("mcu: refused by the XR871 (needs force)");
		return 3;
	}
	out("mcu <- {0x%02lx,0x%02lx} %s", cmd, val, rep.param ? "I2C write FAILED" : "sent");
	pump(1000);		/* replies arrive as MCU events */
	mcu_collect = 0;
	return rep.param ? 1 : 0;
}

/* ---- GPIO test -------------------------------------------------------- */

static int parse_pin(const char *s, int *port)
{
	char *e;
	long n;

	*port = 0;
	if ((s[0] == 'P' || s[0] == 'p') && s[1])
		s++;
	if (s[0] == 'A' || s[0] == 'a') {
		s++;
	} else if (s[0] == 'B' || s[0] == 'b') {
		*port = 1;
		s++;
	}
	n = strtol(s, &e, 10);
	if (*e || !*s || n < 0 || n > 31)
		return -1;
	return n;
}

static int gpio_req(int port, int pin, int mode, unsigned ms, unsigned half)
{
	uint8_t p[7] = { port, pin, mode, ms & 0xff, ms >> 8, half & 0xff, half >> 8 };

	if (request(0xd3, 0, p, sizeof(p), EXT_TIMEOUT_MS))
		return -2;
	if (rep.param == 0xfffe)
		return -3;
	if (rep.param == 0xffff)
		return -1;
	return rep.param;
}

static const char *gpio_err(int r)
{
	return r == -3 ? "refused by the XR871 (protected or in use)" :
	       r == -2 ? "no answer from the XR871" : "failed on the XR871";
}

static int cmd_gpio_scan(char *args)
{
	int pins[24], np = 0, i, secs = 3, port;
	char *t;

	/* gpio scan [seconds] [PAn ...]: a bare number is the time */
	for (t = strtok(args, " "); t; t = strtok(NULL, " ")) {
		if (t[0] >= '0' && t[0] <= '9') {
			secs = atoi(t);
			if (secs < 1 || secs > 60)
				secs = 3;
		} else if (np < 24 && (pins[np] = parse_pin(t, &port)) >= 0 && port == 0) {
			np++;
		} else {
			out("gpio scan: ignoring '%s' (pins are PAn)", t);
		}
	}
	if (!np) {
		/* no default list: PA6/11/13 have unknown roles on this board
		 * (T30 power/reset?), the caller has to name what to drive */
		out("usage: gpio scan [seconds] PAn [PAn ...]   (stock outputs: PA6 PA10 PA11"
		    " PA13 PA14 PA15; PA10 = blue LED, PA11 = red LED, PA15 = SPI ready, refused)");
		return 2;
	}
	out("gpio scan: %d pins, %d s each - watch the LEDs", np, secs);
	for (i = 0; i < np; i++) {
		int r = gpio_req(0, pins[i], 3, secs * 1000 + 500, 250);

		if (r < 0) {
			out("PA%-2d: %s", pins[i], gpio_err(r));
			continue;
		}
		out("PA%-2d: blinking now (%d s)", pins[i], secs);
		pump(secs * 1000);
		gpio_req(0, pins[i], 4, 0, 0);
	}
	out("gpio scan done; repeat one pin with: xr871d -c 'gpio PAn blink 30'");
	return 0;
}

static int cmd_gpio(char *args)
{
	char *a, *m, *t;
	int port, pin, mode, secs = 30, r;

	if (need_bridge())
		return 1;
	while (*args == ' ')
		args++;
	if (!strncmp(args, "scan", 4) && (args[4] == 0 || args[4] == ' '))
		return cmd_gpio_scan(args + 4);
	a = strtok(args, " ");
	m = strtok(NULL, " ");
	t = strtok(NULL, " ");
	if (!a || !m || (pin = parse_pin(a, &port)) < 0) {
		out("usage: gpio <PAn> <0|1|in|blink|off> [seconds] | gpio scan [seconds] [PAn ...]");
		return 2;
	}
	if (!strcmp(m, "0") || !strcmp(m, "low"))
		mode = 0;
	else if (!strcmp(m, "1") || !strcmp(m, "high"))
		mode = 1;
	else if (!strcmp(m, "in") || !strcmp(m, "read"))
		mode = 2;
	else if (!strcmp(m, "blink"))
		mode = 3;
	else if (!strcmp(m, "off") || !strcmp(m, "release"))
		mode = 4;
	else {
		out("gpio: mode is 0, 1, in, blink or off");
		return 2;
	}
	if (t)
		secs = atoi(t);
	if (secs < 1 || secs > 600)
		secs = 30;
	r = gpio_req(port, pin, mode, secs > 65 ? 65000 : secs * 1000, 250);
	if (r < 0) {
		out("P%c%d: %s", 'A' + port, pin, gpio_err(r));
		return 1;
	}
	if (mode == 2)
		out("P%c%d = %d", 'A' + port, pin, r);
	else if (mode == 4)
		out("P%c%d released", 'A' + port, pin);
	else
		out("P%c%d %s for %d s, then released", 'A' + port, pin,
		    mode == 3 ? "blinking" : mode ? "high" : "low", secs > 65 ? 65 : secs);
	return 0;
}

/* ---- application update ------------------------------------------------ */

#define FW_FLASH_SIZE 0x200000u
#define FW_BL_SIZE 0x8000u
#define FW_SLOT_LIMIT 0xfb000u
#define FW_AWIH 0x48495741u
#define FW_BOOT_ID 0xa5ff5a00u
#define FW_APP_ID 0xa5fe5a01u
#define FW_CHUNK 232

static const char *const fwu_err[] = {
	"ok", "wrong state", "bad request", "OTA disabled in the XR871 boot header",
	"image too big for the slot", "chunk crc error", "chunk out of order",
	"flash error", "read-back mismatch", "image check failed", "not verified",
	"OTA config unreadable/full/write failed", "cannot tell which image runs",
	"no flash access in this firmware", "address outside the writable window",
	"boot header unusable"
};

static const char *fwu_errstr(unsigned e)
{
	return e < sizeof(fwu_err) / sizeof(fwu_err[0]) ? fwu_err[e] : "?";
}

static uint32_t crc32_z(uint32_t crc, const uint8_t *p, size_t n)
{
	int k;

	crc = ~crc;
	while (n--) {
		crc ^= *p++;
		for (k = 0; k < 8; k++)
			crc = (crc >> 1) ^ (0xedb88320u & -(crc & 1));
	}
	return ~crc;
}

static uint16_t sum16(const uint8_t *p, size_t n, uint16_t s)
{
	while (n > 1) {
		s += p[0] | p[1] << 8;
		p += 2;
		n -= 2;
	}
	if (n)
		s += p[0];
	return s;
}

/* load a full 2 MiB flash image or a chain starting with the APP section
 * (image offset 0x8000); returns the span from 0x8000, checked with the
 * bootloader's rules */
static uint8_t *fw_load(const char *path, uint32_t *span_len)
{
	FILE *f = fopen(path, "rb");
	uint8_t *buf, *span;
	long size;
	uint32_t delta, off = FW_BL_SIZE, end = 0;
	int i;

	if (!f) {
		out("fwupdate: cannot open %s: %s", path, strerror(errno));
		return NULL;
	}
	fseek(f, 0, SEEK_END);
	size = ftell(f);
	fseek(f, 0, SEEK_SET);
	if (size < 128 || size > (long)FW_FLASH_SIZE) {
		fclose(f);
		out("fwupdate: %s: size %ld is not an XR871 image", path, size);
		return NULL;
	}
	buf = malloc(size);
	if (!buf || fread(buf, 1, size, f) != (size_t)size) {
		fclose(f);
		free(buf);
		out("fwupdate: read error");
		return NULL;
	}
	fclose(f);
	if (rd32(buf) == FW_AWIH && rd32(buf + 36) == FW_BOOT_ID) {
		if (rd32(buf + 32) != FW_BL_SIZE) {
			out("fwupdate: the bootloader in this file is not 0x8000 bytes; the update"
			    " never replaces the bootloader, refused");
			free(buf);
			return NULL;
		}
		delta = 0;		/* full flash image: file offset = image offset */
		out("fwupdate: full flash image, bootloader and data outside the chain ignored");
	} else if (rd32(buf) == FW_AWIH && rd32(buf + 36) == FW_APP_ID) {
		delta = FW_BL_SIZE;	/* chain file: starts at image offset 0x8000 */
	} else {
		out("fwupdate: %s is not an XR871 image (no AWIH app/boot header)", path);
		free(buf);
		return NULL;
	}
	for (i = 0; i < 16; i++) {
		uint32_t fo = off - delta, dsize, blen, next, m;
		const uint8_t *h = buf + fo;

		if (fo + 64 > (uint32_t)size || rd32(h) != FW_AWIH || sum16(h, 64, 0) != 0xffff) {
			out("fwupdate: bad section header at 0x%06x", (unsigned)off);
			goto bad;
		}
		if (i == 0 && rd32(h + 36) != FW_APP_ID) {
			out("fwupdate: first section is not the application");
			goto bad;
		}
		dsize = rd32(h + 12);
		blen = rd32(h + 24);
		next = rd32(h + 32);
		m = dsize > blen ? dsize : blen;
		if (m > (uint32_t)size - fo - 64 ||
		    sum16(h + 64, dsize, h[10] | h[11] << 8) != 0xffff) {
			out("fwupdate: bad data checksum in section 0x%08x at 0x%06x",
			    (unsigned)rd32(h + 36), (unsigned)off);
			goto bad;
		}
		out("  0x%06x id 0x%08x %7u bytes ok", (unsigned)off, (unsigned)rd32(h + 36),
		    (unsigned)blen);
		if (off + 64 + m > end)
			end = off + 64 + m;
		if (next == 0xffffffffu)
			break;
		if (next <= off || next >= FW_SLOT_LIMIT) {
			out("fwupdate: section chain goes backwards / out of the slot");
			goto bad;
		}
		off = next;
	}
	if (i == 16) {
		out("fwupdate: too many sections");
		goto bad;
	}
	if (end > FW_SLOT_LIMIT) {
		out("fwupdate: image ends at 0x%06x, beyond the slot limit 0x%06x",
		    (unsigned)end, (unsigned)FW_SLOT_LIMIT);
		goto bad;
	}
	*span_len = end - FW_BL_SIZE;
	span = malloc(*span_len);
	if (!span)
		goto bad;
	memcpy(span, buf + FW_BL_SIZE - delta, *span_len);
	free(buf);
	return span;
bad:
	free(buf);
	return NULL;
}

static void fw_print_info(const uint8_t *p)
{
	out("xr871: state %s, running image %s, target image %s, OTA %s",
	    p[0] < 5 ? fwu_states[p[0]] : "?",
	    p[1] == 0xff ? "?" : p[1] ? "2" : "1", p[2] == 0xff ? "?" : p[2] ? "2" : "1",
	    p[3] == 0xff ? "?" : p[3] ? "enabled" : "DISABLED");
	if (p[3] != 0xff)
		out("xr871: target window 0x%06x-0x%06x, %u of %u bytes, crc %08x",
		    (unsigned)rd32(p + 4), (unsigned)rd32(p + 20), (unsigned)rd32(p + 8),
		    (unsigned)rd32(p + 12), (unsigned)rd32(p + 16));
}

static int fw_commit(uint32_t crc)
{
	uint8_t c[4];

	out("fwupdate: COMMIT - the XR871 boot config now points to the new image.");
	out("fwupdate: the bootloader falls back to the old image only if the new APP");
	out("fwupdate: section fails its checksum, NOT if the new firmware misbehaves.");
	wr32(c, crc);
	if (request(0xdb, 0xc0ff, c, 4, 30000)) {
		out("fwupdate: no answer to commit - check with 'fwupdate --info'");
		return 1;
	}
	if (rep.param) {
		out("fwupdate: commit refused: %s", fwu_errstr(rep.param));
		return 1;
	}
	out("fwupdate: committed; active after the next XR871 reset ('fwupdate --abort' reverts)");
	return 0;
}

static int fw_reboot(void)
{
	out("fwupdate: rebooting the XR871 (this powers the T30 off)");
	sync();
	if (request(0xdc, 2, NULL, 0, 3000) || rep.param) {
		out("fwupdate: reboot refused: %s", rep.got ? fwu_errstr(rep.param) : "no answer");
		return 1;
	}
	return 0;
}

/* Build number NN of an XR871 bridge firmware "... apNN ...", -1 if unknown.
 * Builds before ap21 lose the WiFi during a transfer (UART FIFO overrun
 * corrupted the WiFi config frame), see fwupdate. */
static int bridge_build(void)
{
	char ver[65];
	const char *q;

	if (request(0xd0, 0, NULL, 0, EXT_TIMEOUT_MS) || rep.plen <= 88)
		return -1;
	memset(ver, 0, sizeof(ver));
	memcpy(ver, rep.p + 88, rep.plen - 88 > 64 ? 64 : rep.plen - 88);
	for (q = ver; (q = strstr(q, "ap")); q += 2)
		if ((q == ver || q[-1] == ' ') && q[2] >= '0' && q[2] <= '9')
			return atoi(q + 2);
	return -1;
}

static int cmd_fwupdate(char *args)
{
	char *t, *file = NULL;
	int commit = 0, reboot = 0, force = 0, info = 0, abort_ = 0, wifi_ok = 0, tries;
	uint32_t len = 0, crc, off, last_pct = 101;
	uint8_t *span, b[24];

	if (need_bridge())
		return 1;
	for (t = strtok(args, " "); t; t = strtok(NULL, " ")) {
		if (!strcmp(t, "--commit"))
			commit = 1;
		else if (!strcmp(t, "--reboot"))
			reboot = 1;
		else if (!strcmp(t, "--force-stage"))
			force = 1;
		else if (!strcmp(t, "--info"))
			info = 1;
		else if (!strcmp(t, "--abort"))
			abort_ = 1;
		else if (!strcmp(t, "--wifi-may-drop"))
			wifi_ok = 1;
		else if (t[0] != '-' && !file)
			file = t;
		else {
			out("fwupdate: unknown option %s", t);
			return 2;
		}
	}
	if (info || abort_ || (!file && (commit || reboot))) {
		if (request(0xdc, abort_, NULL, 0, 5000)) {
			out("fwupdate: no answer from the XR871");
			return 1;
		}
		if (rep.param)
			out("fwupdate: %s", fwu_errstr(rep.param));
		if (rep.plen >= 24)
			fw_print_info(rep.p);
		if (rep.param || info || abort_)
			return rep.param ? 1 : 0;
		if (commit) {
			if (rep.p[0] != 3) {
				out("fwupdate: nothing verified to commit");
				return 1;
			}
			if (fw_commit(rd32(rep.p + 16)))
				return 1;
		}
		return reboot ? fw_reboot() : 0;
	}
	if (!file) {
		out("usage: fwupdate <file> [--commit] [--reboot] [--force-stage] | --info | --abort | --commit");
		return 2;
	}
	/* XR871 builds before ap21 broke the WPA handshake during a transfer
	 * until the next XR871 reboot (2026-11-21, camera 2); ap21 fixed it.
	 * Older builds still need the explicit opt-in. */
	if (!wifi_ok) {
		int nn = bridge_build();

		if (nn >= 0 && nn < 21) {
			out("fwupdate: XR871 build ap%d loses the WiFi during a transfer (fixed in ap21);", nn);
			out("fwupdate: add --wifi-may-drop to do it anyway (needs a console or power cycle to recover)");
			return 2;
		}
	}
	span = fw_load(file, &len);
	if (!span)
		return 1;
	crc = crc32_z(0, span, len);
	out("fwupdate: %u bytes (image offsets 0x%06x-0x%06x), crc32 %08x",
	    (unsigned)len, (unsigned)FW_BL_SIZE, (unsigned)(FW_BL_SIZE + len), (unsigned)crc);
	wr32(b, 0x31555746u);
	wr32(b + 4, FW_BL_SIZE);
	wr32(b + 8, len);
	wr32(b + 12, crc);
	b[16] = FW_CHUNK;
	b[17] = 0;
	b[18] = (force ? 1 : 0) | 2;	/* resume an identical transfer */
	b[19] = 0;
	wr32(b + 20, 0);
	if (request(0xd8, 0, b, sizeof(b), 5000)) {
		out("fwupdate: no answer from the XR871");
		goto fail;
	}
	if (rep.plen >= 24)
		fw_print_info(rep.p);
	if (rep.param) {
		out("fwupdate: refused: %s", fwu_errstr(rep.param));
		if (rep.param == 3)
			out("fwupdate: this XR871 flash was built without the stock OTA area, so the"
			    " bootloader only ever boots image 1; see README (re-enable OTA by clip)."
			    " --force-stage writes image 2 anyway (transfer test, never activated)");
		goto fail;
	}
	off = rd32(rep.p + 8);
	if (off)
		out("fwupdate: resuming at %u", (unsigned)off);
	while (off < len) {
		uint8_t d[8 + FW_CHUNK];
		uint32_t n = len - off < FW_CHUNK ? len - off : FW_CHUNK, fill = 0, pct;
		int r = -1;

		/* 0xff runs are not sent, only erased and checked */
		while (off + fill < len && fill < 16384 && span[off + fill] == 0xff)
			fill++;
		if (fill < 64 && off + fill < len)
			fill = 0;
		for (tries = 0; tries < 5; tries++) {
			wr32(d, off);
			if (fill) {
				wr32(d + 4, fill);
				r = request(0xd9, 1, d, 8, 10000);
			} else {
				wr32(d + 4, crc32_z(0, span + off, n));
				memcpy(d + 8, span + off, n);
				r = request(0xd9, 0, d, 8 + n, 5000);
			}
			if (!r)
				break;
			out("fwupdate: no answer at %u, retrying", (unsigned)off);
		}
		if (r) {
			out("fwupdate: XR871 stopped answering at %u; run the same command again to resume",
			    (unsigned)off);
			goto fail;
		}
		if (rep.param) {
			out("fwupdate: chunk at %u: %s", (unsigned)off, fwu_errstr(rep.param));
			goto fail;
		}
		off = rep.plen >= 4 ? rd32(rep.p) : off + (fill ? fill : n);
		pct = (uint64_t)off * 100 / len;
		if (pct / 10 != last_pct / 10) {
			out("fwupdate: %3u%% (%u/%u)", (unsigned)pct, (unsigned)off, (unsigned)len);
			last_pct = pct;
		}
	}
	free(span);
	span = NULL;
	out("fwupdate: verifying on the XR871 (read back + section checksums)");
	if (request(0xda, 0, NULL, 0, 30000)) {
		out("fwupdate: no answer to verify");
		return 1;
	}
	if (rep.param) {
		out("fwupdate: VERIFY FAILED: %s (crc %08x, at 0x%06x)", fwu_errstr(rep.param),
		    rep.plen >= 4 ? (unsigned)rd32(rep.p) : 0,
		    rep.plen >= 12 ? (unsigned)rd32(rep.p + 8) : 0);
		return 1;
	}
	out("fwupdate: verified: crc %08x, %u sections", (unsigned)rd32(rep.p), rep.p[4]);
	if (!commit) {
		out("fwupdate: staged only; activate with 'fwupdate --commit'"
		    " (boot config switch, see README for what is verified)");
		return 0;
	}
	if (fw_commit(crc))
		return 1;
	return reboot ? fw_reboot() : 0;
fail:
	free(span);
	return 1;
}

/* returns -1 if c is not an extension command, else the exit code (after
 * answering the caller) */
static int ext_command(char *c)
{
	int rc;

	if (!strcmp(c, "status"))
		rc = cmd_status();
	else if (!strncmp(c, "mcu ", 4))
		rc = cmd_mcu(c + 4);
	else if (!strncmp(c, "gpio ", 5))
		rc = cmd_gpio(c + 5);
	else if (!strncmp(c, "fwupdate", 8) && (c[8] == ' ' || !c[8]))
		rc = cmd_fwupdate(c + 8);
	else
		return -1;
	out_end(rc);
	cli_len = 0;
	return rc;
}
