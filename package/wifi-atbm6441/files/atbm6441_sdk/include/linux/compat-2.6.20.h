#ifndef LINUX_26_20_COMPAT_H
#define LINUX_26_20_COMPAT_H

#include <linux/version.h>

/* Compat work for 2.6.20 */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,20))

#include <linux/workqueue.h>

typedef void (*work_func_t)(struct work_struct *work);
typedef void (*compat_work_func_t)(void *work);
static inline void (INIT_WORK)(struct work_struct *work, work_func_t func)
{
	INIT_WORK(work, (compat_work_func_t)func, work);
}
#undef INIT_WORK

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,20)) */

#endif /* LINUX_26_20_COMPAT_H */
