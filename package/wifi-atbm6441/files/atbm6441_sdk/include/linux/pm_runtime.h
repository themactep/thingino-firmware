#include <linux/version.h>

#ifndef __COMPAT_LINUX_PM_RUNTIME_H
#define __COMPAT_LINUX_PM_RUNTIME_H

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,32))
#include_next <linux/pm_runtime.h>
#else

static inline void pm_runtime_enable(struct device *dev) {}

#endif /* (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,32)) */

#endif
