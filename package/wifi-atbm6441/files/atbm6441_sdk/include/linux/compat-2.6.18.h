#ifndef LINUX_26_18_COMPAT_H
#define LINUX_26_18_COMPAT_H

#include <linux/version.h>

/* Compat work for 2.6.18 */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,18))

#define roundup(x, y)	((((x) + ((y) - 1)) / (y)) * (y))

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,18)) */

#endif /* LINUX_26_18_COMPAT_H */
