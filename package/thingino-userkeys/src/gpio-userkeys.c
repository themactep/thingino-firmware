// SPDX-License-Identifier: GPL-2.0
/*
 * gpio-userkeys for XBurst2 / kernel 4.4: registers a "gpio-keys" platform
 * device from a module parameter, like the 3.10 SDK module of the same name
 * (same parameter format, so /etc/modules.d/gpio-userkeys is shared).
 *
 *   modprobe gpio-userkeys gpio_config="28,62,1;2,63,1"
 *
 * Each entry is <input key code>,<gpio>[,<active_low>]; entries separated by
 * ';'.  Code 28 = KEY_ENTER (reset button for thingino-button).
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/gpio_keys.h>
#include <linux/input.h>
#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/slab.h>

#define MAXKEYS 8

static char *gpio_config;
module_param(gpio_config, charp, 0444);
MODULE_PARM_DESC(gpio_config, "<code>,<gpio>[,<active_low>][;...]");

static struct gpio_keys_button btn[MAXKEYS];
static char desc[MAXKEYS][16];
static struct gpio_keys_platform_data pdata = { .buttons = btn };
static struct platform_device *pdev;

static int __init ukeys_init(void)
{
	char *buf, *p, *ent;

	if (!gpio_config || !*gpio_config)
		return -ENODEV;
	buf = kstrdup(gpio_config, GFP_KERNEL);
	if (!buf)
		return -ENOMEM;
	p = buf;
	while ((ent = strsep(&p, ";")) && pdata.nbuttons < MAXKEYS) {
		unsigned int code, gpio, low = 1;
		int n = sscanf(ent, "%u,%u,%u", &code, &gpio, &low);

		if (n < 2)
			continue;
		snprintf(desc[pdata.nbuttons], sizeof(desc[0]), "gpio%u", gpio);
		btn[pdata.nbuttons].code = code;
		btn[pdata.nbuttons].gpio = gpio;
		btn[pdata.nbuttons].active_low = !!low;
		btn[pdata.nbuttons].type = EV_KEY;
		btn[pdata.nbuttons].desc = desc[pdata.nbuttons];
		btn[pdata.nbuttons].debounce_interval = 30;
		pdata.nbuttons++;
	}
	kfree(buf);
	if (!pdata.nbuttons)
		return -EINVAL;
	pdev = platform_device_register_data(NULL, "gpio-keys", PLATFORM_DEVID_AUTO,
					     &pdata, sizeof(pdata));
	return PTR_ERR_OR_ZERO(pdev);
}

static void __exit ukeys_exit(void)
{
	platform_device_unregister(pdev);
}

module_init(ukeys_init);
module_exit(ukeys_exit);
MODULE_DESCRIPTION("GPIO keys registration via module parameter (thingino)");
MODULE_LICENSE("GPL");
