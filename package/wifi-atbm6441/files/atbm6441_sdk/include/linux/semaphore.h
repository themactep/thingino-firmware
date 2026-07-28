#ifndef _COMPAT_LINUX_SEMAPHORE_H
#define _COMPAT_LINUX_SEMAPHORE_H 1

#include <linux/version.h>

#if (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,25))
#include_next <linux/semaphore.h>
#else
#include <asm/semaphore.h>
#endif /* (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,25)) */

#endif	/* _COMPAT_LINUX_SEMAPHORE_H */
