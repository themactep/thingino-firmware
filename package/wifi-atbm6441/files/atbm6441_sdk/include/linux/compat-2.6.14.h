#ifndef LINUX_26_14_COMPAT_H
#define LINUX_26_14_COMPAT_H

#include <linux/version.h>

/* Compat work for 2.6.14 */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14))

typedef unsigned int gfp_t;

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,14)) */

#endif /* LINUX_26_14_COMPAT_H */
