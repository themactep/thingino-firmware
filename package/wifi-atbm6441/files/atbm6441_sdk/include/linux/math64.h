#ifndef _COMPAT_LINUX_MATH64_H
#define _COMPAT_LINUX_MATH64_H 1

#include <linux/version.h>

#if (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,25))
#include_next <linux/math64.h>
#endif /* (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,25)) */

#endif	/* _COMPAT_LINUX_MATH64_H */
