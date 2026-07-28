#ifndef LINUX_26_39_COMPAT_H
#define LINUX_26_39_COMPAT_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,39))

#include <linux/tty.h>
#include <linux/irq.h>
#include <linux/kernel.h>

#define tiocmget(tty) tiocmget(tty, NULL)
#define tiocmset(tty, set, clear) tiocmset(tty, NULL, set, clear)

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,27))
extern int tty_set_termios(struct tty_struct *tty, struct ktermios *kt);
#endif /* (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,27)) */

static inline int irq_set_irq_wake(unsigned int irq, unsigned int on)
{
	return set_irq_wake(irq, on);
}
static inline int irq_set_chip(unsigned int irq, struct irq_chip *chip)
{
	return set_irq_chip(irq, chip);
}
static inline int irq_set_handler_data(unsigned int irq, void *data)
{
	return set_irq_data(irq, data);
}
static inline int irq_set_chip_data(unsigned int irq, void *data)
{
	return set_irq_chip_data(irq, data);
}
static inline int irq_set_irq_type(unsigned int irq, unsigned int type)
{
	return set_irq_type(irq, type);
}
static inline int irq_set_msi_desc(unsigned int irq, struct msi_desc *entry)
{
	return set_irq_msi(irq, entry);
}
static inline struct irq_chip *irq_get_chip(unsigned int irq)
{
	return get_irq_chip(irq);
}
static inline void *irq_get_chip_data(unsigned int irq)
{
	return get_irq_chip_data(irq);
}
static inline void *irq_get_handler_data(unsigned int irq)
{
	return get_irq_data(irq);
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,37))
static inline void *irq_data_get_irq_handler_data(struct irq_data *d)
{
	return irq_data_get_irq_data(d);
}
#endif

static inline struct msi_desc *irq_get_msi_desc(unsigned int irq)
{
	return get_irq_msi(irq);
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,25))
static inline void irq_set_noprobe(unsigned int irq)
{
	set_irq_noprobe(irq);
}
static inline void irq_set_probe(unsigned int irq)
{
	set_irq_probe(irq);
}
#endif

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,29))
static inline struct irq_chip *irq_desc_get_chip(struct irq_desc *desc)
{
	return get_irq_desc_chip(desc);
}
static inline void *irq_desc_get_handler_data(struct irq_desc *desc)
{
	return get_irq_desc_data(desc);
}

static inline void *irq_desc_get_chip_data(struct irq_desc *desc)
{
	return get_irq_desc_chip_data(desc);
}

static inline struct msi_desc *irq_desc_get_msi_desc(struct irq_desc *desc)
{
	return get_irq_desc_msi(desc);
}
#endif /* (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,29)) */

/* 
 * kstrto* was included in kernel 2.6.38.4 and causes conflicts with the
 * version included in compat-wireless. We use strict_strtol to check if
 * kstrto* is already available.
 */
#ifndef strict_strtol
/* Internal, do not use. */
int __must_check _kstrtoul(const char *s, unsigned int base, unsigned long *res);
int __must_check _kstrtol(const char *s, unsigned int base, long *res);

int __must_check kstrtoull(const char *s, unsigned int base, unsigned long long *res);
int __must_check kstrtoll(const char *s, unsigned int base, long long *res);
static inline int __must_check kstrtoul(const char *s, unsigned int base, unsigned long *res)
{
	/*
	 * We want to shortcut function call, but
	 * __builtin_types_compatible_p(unsigned long, unsigned long long) = 0.
	 */
	if (sizeof(unsigned long) == sizeof(unsigned long long) &&
	    __alignof__(unsigned long) == __alignof__(unsigned long long))
		return kstrtoull(s, base, (unsigned long long *)res);
	else
		return _kstrtoul(s, base, res);
}

static inline int __must_check kstrtol(const char *s, unsigned int base, long *res)
{
	/*
	 * We want to shortcut function call, but
	 * __builtin_types_compatible_p(long, long long) = 0.
	 */
	if (sizeof(long) == sizeof(long long) &&
	    __alignof__(long) == __alignof__(long long))
		return kstrtoll(s, base, (long long *)res);
	else
		return _kstrtol(s, base, res);
}

int __must_check kstrtouint(const char *s, unsigned int base, unsigned int *res);
int __must_check kstrtoint(const char *s, unsigned int base, int *res);

static inline int __must_check kstrtou64(const char *s, unsigned int base, u64 *res)
{
	return kstrtoull(s, base, res);
}

static inline int __must_check kstrtos64(const char *s, unsigned int base, s64 *res)
{
	return kstrtoll(s, base, res);
}

static inline int __must_check kstrtou32(const char *s, unsigned int base, u32 *res)
{
	return kstrtouint(s, base, res);
}

static inline int __must_check kstrtos32(const char *s, unsigned int base, s32 *res)
{
	return kstrtoint(s, base, res);
}

int __must_check kstrtou16(const char *s, unsigned int base, u16 *res);
int __must_check kstrtos16(const char *s, unsigned int base, s16 *res);
int __must_check kstrtou8(const char *s, unsigned int base, u8 *res);
int __must_check kstrtos8(const char *s, unsigned int base, s8 *res);
#endif /* ifndef strict_strtol */

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,39)) */

#endif /* LINUX_26_39_COMPAT_H */
