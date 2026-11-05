// SPDX-License-Identifier: GPL-2.0
/*
 * Combined init for the T20 soc_vpu stack.
 *
 * The channel device (soc_vpu.c) allocates its free lists from the VPU
 * nodes registered by the backend (jz_nvpu.c), so the backend driver has
 * to probe before the misc device is registered.  Keep both halves in one
 * module to make that ordering explicit.
 */

#include <linux/init.h>
#include <linux/module.h>

int __init soc_channel_init(void);
void __exit soc_channel_exit(void);
int __init jz_vpu_driver_register(void);
void jz_vpu_driver_unregister(void);

static int __init soc_vpu_module_init(void)
{
	int ret;

	ret = jz_vpu_driver_register();
	if (ret)
		return ret;

	ret = soc_channel_init();
	if (ret)
		jz_vpu_driver_unregister();

	return ret;
}

static void __exit soc_vpu_module_exit(void)
{
	soc_channel_exit();
	jz_vpu_driver_unregister();
}

module_init(soc_vpu_module_init);
module_exit(soc_vpu_module_exit);

MODULE_DESCRIPTION("Ingenic T20 soc_vpu / Helix encoder");
MODULE_AUTHOR("Ingenic Semiconductor");
MODULE_LICENSE("GPL");
