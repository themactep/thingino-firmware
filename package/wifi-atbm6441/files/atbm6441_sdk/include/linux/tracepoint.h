#ifndef _COMPAT_LINUX_TRACEPOINT_H
#define _COMPAT_LINUX_TRACEPOINT_H 1

#include <linux/version.h>

#if (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,27))
#include_next <linux/tracepoint.h>
#endif /* (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,27)) */

#endif	/* _COMPAT_LINUX_TRACEPOINT_H */
