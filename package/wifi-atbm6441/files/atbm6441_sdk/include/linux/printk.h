#ifndef _COMPAT_LINUX_PRINTK_H
#define _COMPAT_LINUX_PRINTK_H 1

#include <linux/version.h>

#if (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,36))
#include_next <linux/printk.h>
#else
#include <linux/kernel.h>
#endif /* (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,35)) */

#endif	/* _COMPAT_LINUX_PRINTK_H */
