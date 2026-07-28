#ifndef __COMPAT_RFKILL_H
#define __COMPAT_RFKILL_H

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,31))

#include_next <linux/rfkill.h>

#else

#include <linux/compat-2.6.h>

#undef CONFIG_RFKILL
#undef CONFIG_RFKILL_INPUT
#undef CONFIG_RFKILL_LEDS

#ifdef CONFIG_RFKILL_BACKPORT
#define CONFIG_RFKILL 1
#endif

#ifdef CONFIG_RFKILL_BACKPORT_INPUT
#define CONFIG_RFKILL_INPUT
#endif

#ifdef CONFIG_RFKILL_BACKPORT_LEDS
#define CONFIG_RFKILL_LEDS
#endif

#include <linux/rfkill_backport.h>

#endif

#endif
