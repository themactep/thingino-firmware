#ifndef _COMPAT_LINUX_EXPORT_H
#define _COMPAT_LINUX_EXPORT_H 1

#include <linux/version.h>

//#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3,2,0))
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3,0,86))
#include_next <linux/export.h>
#else
#include <linux/module.h>
#endif /* (LINUX_VERSION_CODE >= KERNEL_VERSION(3,2,0)) */

#endif	/* _COMPAT_LINUX_EXPORT_H */
