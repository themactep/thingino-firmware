#ifndef LINUX_26_COMPAT_H
#define LINUX_26_COMPAT_H

#include <linux/version.h>
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3,1,0))
#include <linux/kconfig.h>
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,33))
#include <generated/autoconf.h>
#else
#include <linux/autoconf.h>
#endif

/* STERICSSON_WLAN_BUILT_IN hack*/
#ifndef COMPAT_STATIC
#include <linux/compat_autoconf.h>
#endif

/*
 * Each compat file represents compatibility code for new kernel
 * code introduced for *that* kernel revision.
 */

#include <linux/compat-2.6.22.h>
#include <linux/compat-2.6.23.h>
#include <linux/compat-2.6.24.h>
#include <linux/compat-2.6.25.h>
#include <linux/compat-2.6.26.h>
#include <linux/compat-2.6.27.h>
#include <linux/compat-2.6.28.h>
#include <linux/compat-2.6.29.h>
#include <linux/compat-2.6.30.h>
#include <linux/compat-2.6.31.h>
#include <linux/compat-2.6.32.h>
#include <linux/compat-2.6.33.h>
#include <linux/compat-2.6.34.h>
#include <linux/compat-2.6.35.h>
#include <linux/compat-2.6.36.h>
#include <linux/compat-2.6.37.h>
#include <linux/compat-2.6.38.h>
#include <linux/compat-2.6.39.h>
#include <linux/compat-3.0.h>
#include <linux/compat-3.1.h>
#include <linux/compat-3.2.h>
#include <linux/compat-3.3.h>
#include <linux/compat-3.4.h>
#include <linux/compat-3.5.h>
#include <linux/compat-3.8.h>
#include <linux/compat-3.10.h>
#endif /* LINUX_26_COMPAT_H */
