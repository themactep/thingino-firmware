#ifndef _COMPAT_LINUX_OF_H
#define _COMPAT_LINUX_OF_H 1

#include <linux/version.h>

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,34))
#include_next <linux/of.h>
#else

#ifdef CONFIG_OF
#include_next <linux/of.h>
#endif /* CONFIG_OF */

#endif /* (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,34)) */

#endif	/* _COMPAT_LINUX_OF_H */
