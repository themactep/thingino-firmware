/*
 * Reproduce the Wyze VDB2 stock speaker_ctl.ko GPIO58 PA waveform.
 *
 * Thingino's audio driver owns GPIO58, so the legacy sysfs GPIO API cannot
 * claim it.  This diagnostic writes the T31 GPIO-B PAT0 set/clear aliases
 * directly and verifies the physical input level.  It is intentionally not
 * installed by the production package.
 */
#include <errno.h>
#include <fcntl.h>
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
#define GPIO_PAT0 0x40u
#define GPIO_PAT0S 0x44u
#define GPIO_PAT0C 0x48u
#define GPIO58_MASK (1u << 26)

static volatile uint32_t *gpio;

static void delay_us(unsigned int usec)
{
	struct timeval start;
	struct timeval now;
	uint64_t deadline;

	if (gettimeofday(&start, NULL) != 0) {
		perror("gettimeofday");
		exit(EXIT_FAILURE);
	}
	deadline = (uint64_t)start.tv_sec * 1000000u +
		(uint64_t)start.tv_usec + usec;
	do {
		if (gettimeofday(&now, NULL) != 0) {
			perror("gettimeofday");
			exit(EXIT_FAILURE);
		}
	} while ((uint64_t)now.tv_sec * 1000000u +
		(uint64_t)now.tv_usec < deadline);
}

static void set_level(int high)
{
	gpio[(high ? GPIO_PAT0S : GPIO_PAT0C) / sizeof(uint32_t)] = GPIO58_MASK;
	__sync_synchronize();
}

static int pin_level(void)
{
	return !!(gpio[GPIO_PIN / sizeof(uint32_t)] & GPIO58_MASK);
}

static void print_status(void)
{
	printf("gpio58_pin=%d gpio58_latch=%d\n", pin_level(),
	       !!(gpio[GPIO_PAT0 / sizeof(uint32_t)] & GPIO58_MASK));
}

int main(int argc, char **argv)
{
	int fd;
	void *map;

	if (argc != 2 || (strcmp(argv[1], "status") != 0 &&
			  strcmp(argv[1], "low") != 0 &&
			  strcmp(argv[1], "high") != 0 &&
			  strcmp(argv[1], "mode3") != 0)) {
		fprintf(stderr, "usage: %s {status|low|high|mode3}\n", argv[0]);
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

	if (strcmp(argv[1], "low") == 0) {
		set_level(0);
	} else if (strcmp(argv[1], "high") == 0) {
		set_level(1);
	} else if (strcmp(argv[1], "mode3") == 0) {
		/* Exact transition order in stock speakerctl_ioctl(command 3). */
		set_level(0);
		delay_us(1200);
		set_level(1);
		delay_us(5);
		set_level(0);
		delay_us(5);
		set_level(1);
		delay_us(5);
		set_level(0);
		delay_us(5);
		set_level(1);
		delay_us(100);
	}

	print_status();
	munmap(map, GPIOB_SIZE);
	close(fd);
	return EXIT_SUCCESS;
}
