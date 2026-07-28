#ifndef LINUX_26_38_COMPAT_H
#define LINUX_26_38_COMPAT_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,38))

#include <linux/kernel.h>
#include <linux/skbuff.h>
#include <linux/etherdevice.h>

/* rename member in struct mmc_host in include/linux/mmc/host.h */
#define max_segs	max_hw_segs


/* Exponentially weighted moving average (EWMA) */

/* For more documentation see lib/average.c */
#define pr_warn pr_warning
#define create_freezable_workqueue create_freezeable_workqueue

static inline int skb_checksum_start_offset(const struct sk_buff *skb)
{
	return skb->csum_start - skb_headroom(skb);
}

/* from include/linux/printk.h */ 
#define pr_emerg_once(fmt, ...)					\
	printk_once(KERN_EMERG pr_fmt(fmt), ##__VA_ARGS__)
#define pr_alert_once(fmt, ...)					\
	printk_once(KERN_ALERT pr_fmt(fmt), ##__VA_ARGS__)
#define pr_crit_once(fmt, ...)					\
	printk_once(KERN_CRIT pr_fmt(fmt), ##__VA_ARGS__)
#define pr_err_once(fmt, ...)					\
	printk_once(KERN_ERR pr_fmt(fmt), ##__VA_ARGS__)
#define pr_warn_once(fmt, ...)					\
	printk_once(KERN_WARNING pr_fmt(fmt), ##__VA_ARGS__)
#define pr_notice_once(fmt, ...)				\
	printk_once(KERN_NOTICE pr_fmt(fmt), ##__VA_ARGS__)
#define pr_info_once(fmt, ...)					\
	printk_once(KERN_INFO pr_fmt(fmt), ##__VA_ARGS__)
#define pr_cont_once(fmt, ...)					\
	printk_once(KERN_CONT pr_fmt(fmt), ##__VA_ARGS__)
#if defined(DEBUG)
#define pr_debug_once(fmt, ...)					\
	printk_once(KERN_DEBUG pr_fmt(fmt), ##__VA_ARGS__)
#else
#define pr_debug_once(fmt, ...)					\
	no_printk(KERN_DEBUG pr_fmt(fmt), ##__VA_ARGS__)
#endif

/* include/linux/netdevice.h */
#define alloc_netdev_mqs(sizeof_priv, name, setup, txqs, rxqs) \
	alloc_netdev_mq(sizeof_priv, name, setup, \
			max_t(unsigned int, txqs, rxqs))

#define ETH_P_LINK_CTL	0x886c		/* HPNA, wlan link local tunnel */

/**
 * is_unicast_ether_addr - Determine if the Ethernet address is unicast
 * @addr: Pointer to a six-byte array containing the Ethernet address
 *
 * Return true if the address is a unicast address.
 */
static inline int is_unicast_ether_addr(const u8 *addr)
{
	return !is_multicast_ether_addr(addr);
}

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,38)) */

#endif /* LINUX_26_38_COMPAT_H */
