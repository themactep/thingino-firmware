// SPDX-License-Identifier: GPL-2.0
/*
 * thingino-leds: registers a "leds-gpio" platform device from module
 * parameters, so /sys/class/leds/led_* exists on kernels without a board
 * file (XBurst2 / 4.4).  Usage: insmod thingino-leds.ko led_r=81,1 led_b=82,1
 * Each parameter is <gpio>[,<active_low>].
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/leds.h>
#include <linux/gpio.h>

#define NLED 6
static const char *const names[NLED] = { "led_b", "led_g", "led_r", "led_w", "led_y", "led_v" };
static int p_b[2] = { -1, 0 }, p_g[2] = { -1, 0 }, p_r[2] = { -1, 0 };
static int p_w[2] = { -1, 0 }, p_y[2] = { -1, 0 }, p_v[2] = { -1, 0 };
static int n_b, n_g, n_r, n_w, n_y, n_v;
module_param_array_named(led_b, p_b, int, &n_b, 0444);
module_param_array_named(led_g, p_g, int, &n_g, 0444);
module_param_array_named(led_r, p_r, int, &n_r, 0444);
module_param_array_named(led_w, p_w, int, &n_w, 0444);
module_param_array_named(led_y, p_y, int, &n_y, 0444);
module_param_array_named(led_v, p_v, int, &n_v, 0444);
MODULE_PARM_DESC(led_r, "GPIO[,active_low] of led_r (also led_b/g/w/y/v)");

static struct gpio_led leds[NLED];
static struct gpio_led_platform_data pdata = { .leds = leds };
static struct platform_device *pdev;

static int __init tleds_init(void)
{
	int *p[NLED] = { p_b, p_g, p_r, p_w, p_y, p_v };
	int i;

	for (i = 0; i < NLED; i++) {
		if (p[i][0] < 0)
			continue;
		leds[pdata.num_leds].name = names[i];
		leds[pdata.num_leds].gpio = p[i][0];
		leds[pdata.num_leds].active_low = !!p[i][1];
		leds[pdata.num_leds].default_state = LEDS_GPIO_DEFSTATE_OFF;
		pdata.num_leds++;
	}
	if (!pdata.num_leds)
		return -ENODEV;
	pdev = platform_device_register_data(NULL, "leds-gpio", PLATFORM_DEVID_AUTO,
					     &pdata, sizeof(pdata));
	return PTR_ERR_OR_ZERO(pdev);
}

static void __exit tleds_exit(void)
{
	platform_device_unregister(pdev);
}

module_init(tleds_init);
module_exit(tleds_exit);
MODULE_DESCRIPTION("Thingino GPIO LED registration via module parameters");
MODULE_LICENSE("GPL");
