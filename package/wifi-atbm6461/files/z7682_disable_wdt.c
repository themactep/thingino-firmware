/*
 * MCU watchdog disabler for ATBM6461-based cameras (Wansview A1 / AJCloud ZRT platform).
 *
 * Reconstructed from the stripped MIPS binary extracted from the ZRT recovery initramfs.
 * The binary sends RTOS command 0x13 to the ATBM6461 MCU via /dev/atbm_ioctl (librtos.so).
 * If the watchdog is not disabled or fed, the device reboots after ~13 seconds.
 *
 * Link: -lrtos  (librtos.so from stock recovery; provides rtos_cmd_init/rtos_cmd_send)
 */

#include <stdio.h>

#define RTOS_CMD_DISABLE_MCU_WDT  0x13
#define RTOS_CMD_TIMEOUT_MS       5000

int rtos_cmd_init(void);
int rtos_cmd_send(int cmd_id, void *in_data, int in_len,
		  void *out_data, int *out_len, int timeout_ms);

int main(void)
{
	int ret;

	rtos_cmd_init();

	ret = rtos_cmd_send(RTOS_CMD_DISABLE_MCU_WDT,
			    NULL, 0, NULL, NULL,
			    RTOS_CMD_TIMEOUT_MS);

	puts(ret < 0 ? "disable mcu wdt fail." : "disable mcu wdt success.");

	return 0;
}
