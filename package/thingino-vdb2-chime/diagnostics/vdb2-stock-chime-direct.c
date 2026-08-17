/*
 * Reproduce the Wyze VDB2 stock mechanical-chime GPIO sequence through the
 * T31 GPIO-B registers, bypassing sysfs and shell process timing entirely.
 *
 * This is a bench diagnostic.  It is intentionally not installed by the
 * production package.  The stock-derived pin assignment is:
 *
 *   GPIO59/PB27  supply stage 1
 *   GPIO52/PB20  supply stage 2
 *   GPIO53/PB21  chime trigger
 *   GPIO51/PB19  energy-ready input
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/time.h>
#include <unistd.h>

#define GPIOB_BASE 0x10011000u
#define GPIOB_SIZE 0x1000u

#define GPIO_PIN 0x00u
#define GPIO_INT 0x10u
#define GPIO_INTC 0x18u
#define GPIO_MSK 0x20u
#define GPIO_MSKS 0x24u
#define GPIO_PAT1 0x30u
#define GPIO_PAT1S 0x34u
#define GPIO_PAT1C 0x38u
#define GPIO_PAT0 0x40u
#define GPIO_PAT0S 0x44u
#define GPIO_PAT0C 0x48u
#define GPIO_DOMAIN 0x100u
#define GPIO_PUEN 0x110u
#define GPIO_PUENC 0x118u
#define GPIO_PDEN 0x120u
#define GPIO_PDENC 0x128u
#define GPIO_DRVL 0x130u
#define GPIO_DRVH 0x140u
#define GPIO_SLEW 0x150u
#define GPIO_SCHMITT 0x160u

#define PB19 (1u << 19)
#define PB20 (1u << 20)
#define PB21 (1u << 21)
#define PB27 (1u << 27)

#define STAGE1_MASK PB27
#define STAGE2_MASK PB20
#define TRIGGER_MASK PB21
#define SENSE_MASK PB19
#define OUTPUT_MASK (STAGE1_MASK | STAGE2_MASK | TRIGGER_MASK)
#define CHIME_MASK (OUTPUT_MASK | SENSE_MASK)

#define STOCK_STAGING_PUEN 0x6e094800u
#define STOCK_RUNTIME_PUEN 0x66014800u

static volatile uint32_t *gpio;
static struct timeval trace_start;
static volatile sig_atomic_t interrupted;

static uint32_t reg_read(unsigned int offset)
{
	return gpio[offset / sizeof(uint32_t)];
}

static void reg_write(unsigned int offset, uint32_t value)
{
	gpio[offset / sizeof(uint32_t)] = value;
	__sync_synchronize();
}

static uint64_t now_us(void)
{
	struct timeval now;

	if (gettimeofday(&now, NULL) != 0) {
		perror("gettimeofday");
		exit(EXIT_FAILURE);
	}
	return (uint64_t)now.tv_sec * 1000000u + (uint64_t)now.tv_usec;
}

static uint64_t elapsed_us(void)
{
	uint64_t start = (uint64_t)trace_start.tv_sec * 1000000u +
		(uint64_t)trace_start.tv_usec;

	return now_us() - start;
}

static int delay_us(unsigned int usec)
{
	while (usec != 0) {
		unsigned int chunk = usec > 500000u ? 500000u : usec;

		if (interrupted)
			return -1;
		if (usleep(chunk) != 0 && errno != EINTR) {
			perror("usleep");
			return -1;
		}
		usec -= chunk;
	}
	return interrupted ? -1 : 0;
}

static int level_for(uint32_t mask)
{
	return !!(reg_read(GPIO_PIN) & mask);
}

static void trace_level(const char *name, uint32_t mask)
{
	printf("t_us=%llu %-12s pin=%d latch=%d\n",
	       (unsigned long long)elapsed_us(), name, level_for(mask),
	       !!(reg_read(GPIO_PAT0) & mask));
	fflush(stdout);
}

static int set_level(const char *name, uint32_t mask, int high)
{
	reg_write(high ? GPIO_PAT0S : GPIO_PAT0C, mask);
	trace_level(name, mask);
	if (level_for(mask) != high) {
		fprintf(stderr, "%s failed to reach level %d\n", name, high);
		return -1;
	}
	return 0;
}

static void print_registers(const char *label)
{
	printf("[%s]\n", label);
	printf("PIN=%08x INT=%08x MSK=%08x PAT1=%08x PAT0=%08x\n",
	       reg_read(GPIO_PIN), reg_read(GPIO_INT), reg_read(GPIO_MSK),
	       reg_read(GPIO_PAT1), reg_read(GPIO_PAT0));
	printf("DOMAIN=%08x PUEN=%08x PDEN=%08x DRVL=%08x DRVH=%08x "
	       "SLEW=%08x SCHMITT=%08x\n",
	       reg_read(GPIO_DOMAIN), reg_read(GPIO_PUEN), reg_read(GPIO_PDEN),
	       reg_read(GPIO_DRVL), reg_read(GPIO_DRVH), reg_read(GPIO_SLEW),
	       reg_read(GPIO_SCHMITT));
	printf("stage1=%d stage2=%d trigger=%d energy_ready=%d\n",
	       level_for(STAGE1_MASK), level_for(STAGE2_MASK),
	       level_for(TRIGGER_MASK), level_for(SENSE_MASK));
	fflush(stdout);
}

static int verify_modes(void)
{
	uint32_t value;

	value = reg_read(GPIO_INT);
	if (value & CHIME_MASK) {
		fprintf(stderr, "chime pins remain in interrupt mode: %08x\n", value);
		return -1;
	}
	value = reg_read(GPIO_MSK);
	if ((value & CHIME_MASK) != CHIME_MASK) {
		fprintf(stderr, "chime pins are not all in GPIO mode: %08x\n", value);
		return -1;
	}
	value = reg_read(GPIO_PAT1);
	if ((value & OUTPUT_MASK) != 0 || (value & SENSE_MASK) != SENSE_MASK) {
		fprintf(stderr, "chime pin directions are incorrect: %08x\n", value);
		return -1;
	}
	if (reg_read(GPIO_PUEN) != STOCK_RUNTIME_PUEN) {
		fprintf(stderr, "PUEN=%08x, expected %08x\n", reg_read(GPIO_PUEN),
			STOCK_RUNTIME_PUEN);
		return -1;
	}
	if (reg_read(GPIO_PDEN) & CHIME_MASK) {
		fprintf(stderr, "a chime pin still has a pull-down: %08x\n",
			reg_read(GPIO_PDEN));
		return -1;
	}
	return 0;
}

static int initialize_stock_state(void)
{
	/* Stock app_init.sh state immediately before iCamera starts. */
	reg_write(GPIO_PUEN, STOCK_STAGING_PUEN);

	/* Stock descriptor order: GPIO59, GPIO52, GPIO53 output-low. */
	reg_write(GPIO_INTC, STAGE1_MASK);
	reg_write(GPIO_MSKS, STAGE1_MASK);
	reg_write(GPIO_PAT1C, STAGE1_MASK);
	reg_write(GPIO_PAT0C, STAGE1_MASK);

	reg_write(GPIO_INTC, STAGE2_MASK);
	reg_write(GPIO_MSKS, STAGE2_MASK);
	reg_write(GPIO_PAT1C, STAGE2_MASK);
	reg_write(GPIO_PAT0C, STAGE2_MASK);

	reg_write(GPIO_INTC, TRIGGER_MASK);
	reg_write(GPIO_MSKS, TRIGGER_MASK);
	reg_write(GPIO_PAT1C, TRIGGER_MASK);
	reg_write(GPIO_PAT0C, TRIGGER_MASK);

	/* GPIO51 is the stock energy-ready input. */
	reg_write(GPIO_INTC, SENSE_MASK);
	reg_write(GPIO_MSKS, SENSE_MASK);
	reg_write(GPIO_PAT1S, SENSE_MASK);

	/* jz_gpio_request() disables both pulls as each pin is exported. */
	reg_write(GPIO_PUENC, CHIME_MASK);
	reg_write(GPIO_PDENC, CHIME_MASK);

	print_registers("initialized");
	return verify_modes();
}

static void emergency_low(void)
{
	if (gpio == NULL)
		return;
	reg_write(GPIO_PAT0C, TRIGGER_MASK);
	reg_write(GPIO_PAT0C, STAGE2_MASK);
	reg_write(GPIO_PAT0C, STAGE1_MASK);
}

static void handle_signal(int signo)
{
	(void)signo;
	interrupted = 1;
	if (gpio != NULL) {
		gpio[GPIO_PAT0C / sizeof(uint32_t)] = TRIGGER_MASK;
		gpio[GPIO_PAT0C / sizeof(uint32_t)] = STAGE2_MASK;
		gpio[GPIO_PAT0C / sizeof(uint32_t)] = STAGE1_MASK;
	}
}

static int stock_power_off(void)
{
	int result = 0;

	result |= set_level("trigger-low", TRIGGER_MASK, 0);
	if (delay_us(1000000u) != 0)
		result = -1;
	result |= set_level("stage2-low", STAGE2_MASK, 0);
	if (delay_us(30000u) != 0)
		result = -1;
	result |= set_level("stage1-low", STAGE1_MASK, 0);
	return result;
}

static int stock_ring(unsigned int pulse_ms)
{
	int result = -1;

	if (initialize_stock_state() != 0)
		return -1;
	if (!level_for(SENSE_MASK)) {
		if (delay_us(100000u) != 0)
			return -1;
		if (!level_for(SENSE_MASK)) {
			fprintf(stderr, "energy-ready GPIO51 is low\n");
			return -1;
		}
	}

	/* Exact normal-handler delay: 500 ms plus the enabled-chime 1 second. */
	if (delay_us(1500000u) != 0)
		goto out;
	if (set_level("stage1-high", STAGE1_MASK, 1) != 0)
		goto out;
	if (delay_us(30000u) != 0)
		goto out;
	if (set_level("stage2-high", STAGE2_MASK, 1) != 0)
		goto out;
	if (delay_us(30000u) != 0)
		goto out;
	if (set_level("trigger-high", TRIGGER_MASK, 1) != 0)
		goto out;
	if (delay_us(pulse_ms * 1000u) != 0)
		goto out;
	result = stock_power_off();
	print_registers("after-ring");
	return result;

out:
	emergency_low();
	return result;
}

static int parse_pulse(const char *text, unsigned int *pulse_ms)
{
	char *end;
	unsigned long value;

	errno = 0;
	value = strtoul(text, &end, 10);
	if (errno != 0 || *text == '\0' || *end != '\0' || value < 1 ||
	    value > 5000)
		return -1;
	*pulse_ms = (unsigned int)value;
	return 0;
}

int main(int argc, char **argv)
{
	unsigned int pulse_ms = 200;
	int fd;
	int result = EXIT_FAILURE;
	void *map;

	if (argc < 2 || argc > 3 ||
	    (strcmp(argv[1], "status") != 0 && strcmp(argv[1], "init") != 0 &&
	     strcmp(argv[1], "off") != 0 && strcmp(argv[1], "ring") != 0)) {
		fprintf(stderr, "usage: %s {status|init|off|ring [milliseconds]}\n",
			argv[0]);
		return EXIT_FAILURE;
	}
	if (argc == 3 && (strcmp(argv[1], "ring") != 0 ||
			   parse_pulse(argv[2], &pulse_ms) != 0)) {
		fprintf(stderr, "ring duration must be 1..5000 milliseconds\n");
		return EXIT_FAILURE;
	}
	if (strcmp(argv[1], "ring") == 0 &&
	    (getenv("VDB2_CHIME_LIVE") == NULL ||
	     strcmp(getenv("VDB2_CHIME_LIVE"), "I_UNDERSTAND") != 0)) {
		fprintf(stderr,
			"ring requires VDB2_CHIME_LIVE=I_UNDERSTAND\n");
		return EXIT_FAILURE;
	}

	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		perror("open /dev/mem");
		return EXIT_FAILURE;
	}
	map = mmap(NULL, GPIOB_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd,
		   GPIOB_BASE);
	if (map == MAP_FAILED) {
		perror("mmap GPIO-B");
		close(fd);
		return EXIT_FAILURE;
	}
	gpio = map;
	if (gettimeofday(&trace_start, NULL) != 0) {
		perror("gettimeofday");
		goto done;
	}
	signal(SIGINT, handle_signal);
	signal(SIGTERM, handle_signal);
	signal(SIGHUP, handle_signal);

	if (strcmp(argv[1], "status") == 0) {
		print_registers("status");
		result = EXIT_SUCCESS;
	} else if (strcmp(argv[1], "init") == 0) {
		result = initialize_stock_state() == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
	} else if (strcmp(argv[1], "off") == 0) {
		result = stock_power_off() == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
	} else {
		result = stock_ring(pulse_ms) == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
	}

done:
	if (result != EXIT_SUCCESS)
		emergency_low();
	munmap(map, GPIOB_SIZE);
	gpio = NULL;
	close(fd);
	return result;
}
