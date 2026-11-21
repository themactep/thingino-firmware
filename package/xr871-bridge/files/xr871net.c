/*
 * xr871net - network interface (wlan0) over SPI to the XR871 co-processor.
 *
 * Creates a TAP interface and moves Ethernet frames between it and the
 * XR871 bridge firmware over /dev/spidev0.0 (frame format: spi_frame.h).
 * The T30 is the SPI master: it clocks a frame whenever it has data to
 * send, every POLL_MS when idle, and back to back while the XR871 flags
 * more pending data. Before every transfer it waits for the XR871 ready
 * line (GPIO 77, high = slave buffer armed).
 *
 * Idle frames from the XR871 carry its station MAC and the link state
 * (spi_frame.h). wlan0 takes over that MAC: a WiFi station can only send
 * with its own address. With -U the link is brought up once the MAC is
 * known (or after 3 s).
 *
 * With the stock XR871 firmware the ready line is never raised for this
 * protocol; xr871net then just backs off and does nothing harmful.
 *
 * usage: xr871net [-b] [-v] [-U] [-d /dev/spidev0.0] [-g 77] [-i wlan0]
 *                 [-s hz]
 *   -U  bring the interface up and start udhcpc (tests without the
 *       Thingino network scripts; normally ifup owns wlan0 via
 *       /etc/network/interfaces.d/wlan0)
 * State for "wlan info|rssi" and the WebUI: /run/xr871net.status
 */
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <linux/if_tun.h>
#include <net/if_arp.h>
#include <linux/spi/spidev.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <time.h>
#include <unistd.h>
#include "spi_frame.h"

/* Poll interval for downlink frames: fast while there is traffic, slow
 * when the link has been quiet for ACTIVE_MS (battery). The old rule
 * "5 ms if ready is high, else 50 ms" sampled the line right after a
 * transfer, when the XR871 is still re-arming, and so nearly always
 * waited 50 ms: every frame from the air was delayed up to 50 ms. */
#define FAST_POLL_MS 2
#define IDLE_POLL_MS 20
#define ACTIVE_MS 1000
#define READY_TIMEOUT_MS 100

static const char *spi_dev = "/dev/spidev0.0";
static const char *ifname = "wlan0";
static int ready_gpio = 77;
static uint32_t speed = 10000000;
static int verbose, up_dhcp;
static volatile sig_atomic_t stop;

static unsigned long n_tx, n_rx, n_bad, n_xfer, n_notready;
static long last_traffic;	/* ms of the last data frame, either direction */
static uint8_t cur_mac[6];
static int have_mac, link_state = -1;

static void logk(const char *fmt, ...)
{
	char buf[256];
	va_list ap;
	int n, k;

	n = snprintf(buf, sizeof(buf), "<6>xr871net: ");
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

static long now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000L + t.tv_nsec / 1000000L;
}

static int write_file(const char *path, const char *s)
{
	int f = open(path, O_WRONLY | O_CLOEXEC);
	int r;

	if (f < 0)
		return -1;
	r = write(f, s, strlen(s)) == (ssize_t)strlen(s) ? 0 : -1;
	close(f);
	return r;
}

static int gpio_fd = -1;

static int ready_open(void)
{
	char p[64], n[16];

	if (ready_gpio < 0)
		return 0;
	snprintf(n, sizeof(n), "%d", ready_gpio);
	snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/value", ready_gpio);
	if (access(p, F_OK) != 0)
		write_file("/sys/class/gpio/export", n);
	snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/direction", ready_gpio);
	write_file(p, "in");
	snprintf(p, sizeof(p), "/sys/class/gpio/gpio%d/value", ready_gpio);
	gpio_fd = open(p, O_RDONLY | O_CLOEXEC);
	return gpio_fd >= 0 ? 0 : -1;
}

static int ready(void)
{
	char c = '1';

	if (gpio_fd < 0)
		return 1;
	if (pread(gpio_fd, &c, 1, 0) != 1)
		return 0;
	return c == '1';
}

static int wait_ready(void)
{
	long end = now_ms() + READY_TIMEOUT_MS;

	while (!ready()) {
		if (now_ms() > end)
			return -1;
		usleep(200);
	}
	return 0;
}

static int tap_open(void)
{
	struct ifreq ifr;
	int fd = open("/dev/net/tun", O_RDWR | O_CLOEXEC);

	if (fd < 0)
		return -1;
	memset(&ifr, 0, sizeof(ifr));
	ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
	strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
	if (ioctl(fd, TUNSETIFF, &ifr) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static int spi_open(void)
{
	uint8_t mode = SPI_MODE_1, bits = 8;
	int fd = open(spi_dev, O_RDWR | O_CLOEXEC);

	if (fd < 0)
		return -1;
	if (ioctl(fd, SPI_IOC_WR_MODE, &mode) < 0 ||
	    ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &bits) < 0 ||
	    ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

static int xfer(int fd, const uint8_t *tx, uint8_t *rx)
{
	struct spi_ioc_transfer t;

	memset(&t, 0, sizeof(t));
	t.tx_buf = (unsigned long)tx;
	t.rx_buf = (unsigned long)rx;
	t.len = SPIF_SIZE;
	t.speed_hz = speed;
	t.bits_per_word = 8;
	return ioctl(fd, SPI_IOC_MESSAGE(1), &t) < 0 ? -1 : 0;
}

static int if_flags(int s, int set_up)
{
	struct ifreq ifr;

	memset(&ifr, 0, sizeof(ifr));
	strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
	if (ioctl(s, SIOCGIFFLAGS, &ifr) < 0)
		return -1;
	if (set_up < 0)
		return ifr.ifr_flags & IFF_UP;
	if (set_up)
		ifr.ifr_flags |= IFF_UP;
	else
		ifr.ifr_flags &= ~IFF_UP;
	return ioctl(s, SIOCSIFFLAGS, &ifr);
}

/* give wlan0 the XR871 station MAC; down/up around it if needed */
static void set_mac(const uint8_t *mac)
{
	struct ifreq ifr;
	int s = socket(AF_INET, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	int was_up;

	if (s < 0)
		return;
	memset(&ifr, 0, sizeof(ifr));
	strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
	ifr.ifr_hwaddr.sa_family = ARPHRD_ETHER;
	memcpy(ifr.ifr_hwaddr.sa_data, mac, 6);
	if (ioctl(s, SIOCSIFHWADDR, &ifr) < 0 && errno == EBUSY) {
		was_up = if_flags(s, -1) > 0;
		if_flags(s, 0);
		if (ioctl(s, SIOCSIFHWADDR, &ifr) < 0)
			logk("cannot set MAC: %s", strerror(errno));
		if (was_up)
			if_flags(s, 1);
	}
	close(s);
	memcpy(cur_mac, mac, 6);
	have_mac = 1;
	logk("%s MAC %02x:%02x:%02x:%02x:%02x:%02x (XR871 station)", ifname,
	     mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

static void write_status(int rssi)
{
	FILE *f = fopen("/run/xr871net.status.tmp", "w");

	if (!f)
		return;
	fprintf(f, "link=%s\nrssi=%d\nmac=%02x:%02x:%02x:%02x:%02x:%02x\n",
		link_state ? "up" : "down", rssi, cur_mac[0], cur_mac[1], cur_mac[2],
		cur_mac[3], cur_mac[4], cur_mac[5]);
	fclose(f);
	rename("/run/xr871net.status.tmp", "/run/xr871net.status");
}

static void handle_info(const uint8_t *p)
{
	static const uint8_t zero[6];
	static int last_rssi = 1000;
	static long last_write;
	int rssi = (int8_t)p[7], changed = 0;

	if (memcmp(p, zero, 6) && (!have_mac || memcmp(p, cur_mac, 6))) {
		set_mac(p);
		changed = 1;
	}
	if (p[6] != link_state) {
		link_state = p[6];
		logk("WiFi link %s (rssi %d dBm)", link_state ? "up" : "down", rssi);
		changed = 1;
	}
	/* rssi moves all the time: rewrite at most every 5 s */
	if (changed || (rssi != last_rssi && now_ms() - last_write > 5000)) {
		write_status(rssi);
		last_rssi = rssi;
		last_write = now_ms();
	}
}

static void on_sig(int s)
{
	(void)s;
	stop = 1;
}

int main(int argc, char **argv)
{
	static uint8_t tx[SPIF_SIZE], rx[SPIF_SIZE], pkt[SPIF_MAX_PAYLOAD];
	int bg = 0, c, tap, spi, more = 0;
	uint16_t seq = 0;
	long last_stat = 0, start_ms;

	while ((c = getopt(argc, argv, "bvUd:g:i:s:")) != -1) {
		switch (c) {
		case 'b': bg = 1; break;
		case 'v': verbose = 1; break;
		case 'U': up_dhcp = 1; break;
		case 'd': spi_dev = optarg; break;
		case 'g': ready_gpio = atoi(optarg); break;
		case 'i': ifname = optarg; break;
		case 's': speed = strtoul(optarg, NULL, 0); break;
		default:
			fprintf(stderr, "usage: xr871net [-b] [-v] [-U] [-d dev] [-g gpio] [-i if] [-s hz]\n");
			return 1;
		}
	}
	if (bg) {
		pid_t p = fork();
		if (p < 0)
			return 1;
		if (p > 0)
			return 0;
		setsid();
	}
	signal(SIGTERM, on_sig);
	signal(SIGINT, on_sig);

	tap = tap_open();
	if (tap < 0) {
		logk("cannot create %s: %s", ifname, strerror(errno));
		return 1;
	}
	spi = spi_open();
	if (spi < 0) {
		logk("cannot open %s: %s", spi_dev, strerror(errno));
		return 1;
	}
	if (ready_open() < 0)
		logk("ready gpio %d unavailable, transferring blind", ready_gpio);
	logk("started: %s <-> %s, %u Hz, ready gpio %d", ifname, spi_dev, speed, ready_gpio);

	start_ms = now_ms();
	while (!stop) {
		struct pollfd pf = { tap, POLLIN, 0 };
		int len = 0, r;
		uint8_t type, flags;
		int timeout = more ? 0 :
			(now_ms() - last_traffic < ACTIVE_MS ? FAST_POLL_MS : IDLE_POLL_MS);

		if (up_dhcp && (have_mac || now_ms() - start_ms > 3000)) {
			char cmd[96];

			up_dhcp = 0;
			snprintf(cmd, sizeof(cmd), "ip link set %s up; udhcpc -i %s -b -q -t 20 >/dev/null 2>&1 &",
				 ifname, ifname);
			if (system(cmd) != 0) { /* best effort, test images only */ }
		}

		if (poll(&pf, 1, timeout) > 0 && (pf.revents & POLLIN)) {
			len = read(tap, pkt, sizeof(pkt));
			if (len < 0)
				len = 0;
		}
		if (len > 0)
			spif_build(tx, SPIF_ETH, 0, seq++, pkt, len);
		else
			spif_build(tx, SPIF_IDLE, 0, seq++, NULL, 0);

		if (wait_ready() < 0) {
			if (n_notready == 0 || n_notready == 100)
				logk("XR871 not ready (gpio %d low), count %lu", ready_gpio, n_notready + 1);
			n_notready++;
			more = 0;
			continue;	/* frame from the TAP is dropped, TCP retries */
		}
		if (xfer(spi, tx, rx) < 0) {
			logk("spi transfer failed: %s", strerror(errno));
			usleep(100000);
			continue;
		}
		if (n_xfer++ == 0)
			logk("first SPI transfer done");
		if (len > 0) {
			n_tx++;
			last_traffic = now_ms();
		}

		r = spif_parse(rx, SPIF_SIZE, &type, &flags);
		if (r < 0) {
			if (n_bad == 0)
				logk("first invalid frame from XR871: %02x %02x %02x %02x",
				     rx[0], rx[1], rx[2], rx[3]);
			n_bad++;
			more = 0;
		} else {
			more = flags & SPIF_F_MORE;
			if (type == SPIF_ETH && r > 0) {
				if (write(tap, rx + SPIF_HDR, r) == r)
					n_rx++;
				last_traffic = now_ms();
			} else if (type == SPIF_IDLE && r >= SPIF_INFO_LEN) {
				handle_info(rx + SPIF_HDR);
			}
		}

		if (verbose && now_ms() - last_stat > 10000) {
			last_stat = now_ms();
			logk("xfer %lu tx %lu rx %lu bad %lu notready %lu",
			     n_xfer, n_tx, n_rx, n_bad, n_notready);
		}
	}
	logk("stopping (xfer %lu tx %lu rx %lu bad %lu)", n_xfer, n_tx, n_rx, n_bad);
	return 0;
}
