#ifndef LINUX_3_10_COMPAT_H
#define LINUX_3_10_COMPAT_H

#include <linux/version.h>
#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,10,0))
#define prandom_u32 random32
#endif /* LINUX_3_10_COMPAT_H */
#endif
