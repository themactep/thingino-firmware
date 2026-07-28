#ifndef LINUX_26_27_COMPAT_H
#define LINUX_26_27_COMPAT_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,27))

#include <linux/debugfs.h>
#include <linux/list.h>
#include <linux/pci.h>
#include <linux/dma-mapping.h>
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,24))
#include <linux/mmc/sdio.h>
#include <linux/mmc/sdio_func.h>
#endif /* LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,24) */
#include <linux/netdevice.h>
#include <linux/workqueue.h>
#include <net/iw_handler.h>
#include <asm-generic/bug.h>
#include <linux/wireless.h>
#include <linux/skbuff.h>
#include <net/sch_generic.h>
#include <linux/ethtool.h>

#define PCI_PM_CAP_PME_SHIFT	11

/* I can't find a more suitable replacement... */
#define flush_work(work) cancel_work_sync(work)

struct builtin_fw {
	char *name;
	void *data;
	unsigned long size;
};

/*
 * On older kernels we do not have net_device Multi Queue support, but
 * since we no longer use MQ on mac80211 we can simply use the 0 queue.
 * Note that if other fullmac drivers make use of this they then need
 * to be backported somehow or deal with just 1 queueue from MQ.
 */
static inline void netif_tx_wake_all_queues(struct net_device *dev)
{
	netif_wake_queue(dev);
}
static inline void netif_tx_start_all_queues(struct net_device *dev)
{
	netif_start_queue(dev);
}
static inline void netif_tx_stop_all_queues(struct net_device *dev)
{
	netif_stop_queue(dev);
}

/* Are all TX queues of the device empty?  */
static inline bool qdisc_all_tx_empty(const struct net_device *dev)
{
	return skb_queue_empty(&dev->qdisc->q);
}

bool pci_pme_capable(struct pci_dev *dev, pci_power_t state);

/*
 * The net_device has a spin_lock on newer kernels, on older kernels we're out of luck
 */
#define netif_addr_lock_bh(dev)
#define netif_addr_unlock_bh(dev)

/*
 * To port this properly we'd have to port warn_slowpath_null(),
 * which I'm lazy to do so just do a regular print for now. If you
 * want to port this read kernel/panic.c
 */
#define __WARN_printf(arg...)   do { printk(arg); __WARN(); } while (0)

/* This is ported directly as-is on newer kernels */
#ifndef WARN
#define WARN(condition, format...) ({					\
	int __ret_warn_on = !!(condition);				\
	if (unlikely(__ret_warn_on))					\
		__WARN_printf(format);					\
	unlikely(__ret_warn_on);					\
})
#endif

/* On 2.6.27 a second argument was added, on older kernels we ignore it */
#define dma_mapping_error(pdev, dma_addr) dma_mapping_error(dma_addr)
#define pci_dma_mapping_error(pdev, dma_addr) dma_mapping_error(pdev, dma_addr)

/* This is from include/linux/ieee80211.h */
#define IEEE80211_HT_CAP_DSSSCCK40		0x1000

/* New link list changes added as of 2.6.27, needed for ath9k */

static inline void __list_cut_position(struct list_head *list,
		struct list_head *head, struct list_head *entry)
{
	struct list_head *new_first = entry->next;
	list->next = head->next;
	list->next->prev = list;
	list->prev = entry;
	entry->next = list;
	head->next = new_first;
	new_first->prev = head;
}

/**
 * list_cut_position - cut a list into two
 * @list: a new list to add all removed entries
 * @head: a list with entries
 * @entry: an entry within head, could be the head itself
 *	and if so we won't cut the list
 *
 * This helper moves the initial part of @head, up to and
 * including @entry, from @head to @list. You should
 * pass on @entry an element you know is on @head. @list
 * should be an empty list or a list you do not care about
 * losing its data.
 *
 */
static inline void list_cut_position(struct list_head *list,
		struct list_head *head, struct list_head *entry)
{
	if (list_empty(head))
		return;
	if (list_is_singular(head) &&
		(head->next != entry && head != entry))
		return;
	if (entry == head)
		INIT_LIST_HEAD(list);
	else
		__list_cut_position(list, head, entry);
}


/* __list_splice as re-implemented on 2.6.27, we backport it */
static inline void __compat_list_splice_new_27(const struct list_head *list,
				 struct list_head *prev,
				 struct list_head *next)
{
	struct list_head *first = list->next;
	struct list_head *last = list->prev;

	first->prev = prev;
	prev->next = first;

	last->next = next;
	next->prev = last;
}

/**
 * list_splice_tail - join two lists, each list being a queue
 * @list: the new list to add.
 * @head: the place to add it in the first list.
 */
static inline void list_splice_tail(struct list_head *list,
				struct list_head *head)
{
	if (!list_empty(list))
		__compat_list_splice_new_27(list, head->prev, head);
}

/**
 * list_splice_tail_init - join two lists and reinitialise the emptied list
 * @list: the new list to add.
 * @head: the place to add it in the first list.
 *
 * Each of the lists is a queue.
 * The list at @list is reinitialised
 */
static inline void list_splice_tail_init(struct list_head *list,
					 struct list_head *head)
{
	if (!list_empty(list)) {
		__compat_list_splice_new_27(list, head->prev, head);
		INIT_LIST_HEAD(list);
	}
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,24))
extern unsigned int mmc_align_data_size(struct mmc_card *, unsigned int);
extern unsigned int sdio_align_size(struct sdio_func *func, unsigned int sz);
#endif /* LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,24) */

#define iwe_stream_add_value(info, event, value, ends, iwe, event_len) iwe_stream_add_value(event, value, ends, iwe, event_len)
#define iwe_stream_add_point(info, stream, ends, iwe, extra) iwe_stream_add_point(stream, ends, iwe, extra)
#define iwe_stream_add_event(info, stream, ends, iwe, event_len) iwe_stream_add_event(stream, ends, iwe, event_len)

/* Flags available in struct iw_request_info */
#define IW_REQUEST_FLAG_COMPAT	0x0001	/* Compat ioctl call */

static inline int iwe_stream_lcp_len(struct iw_request_info *info)
{
#ifdef CONFIG_COMPAT
	if (info->flags & IW_REQUEST_FLAG_COMPAT)
		return IW_EV_COMPAT_LCP_LEN;
#endif
	return IW_EV_LCP_LEN;
}

#ifdef CONFIG_ARM

/*
 * The caller asks to handle a range between offset and offset + size,
 * but we process a larger range from 0 to offset + size due to lack of
 * offset support.
 */

static inline void dma_sync_single_range_for_cpu(struct device *dev,
		dma_addr_t handle, unsigned long offset, size_t size,
		enum dma_data_direction dir)
{
	dma_sync_single_for_cpu(dev, handle, offset + size, dir);
}

static inline void dma_sync_single_range_for_device(struct device *dev,
		dma_addr_t handle, unsigned long offset, size_t size,
		enum dma_data_direction dir)
{
	dma_sync_single_for_device(dev, handle, offset + size, dir);
}

#endif /* arm */

#if defined(CONFIG_DEBUG_FS)
void debugfs_remove_recursive(struct dentry *dentry);
#else
static inline void debugfs_remove_recursive(struct dentry *dentry)
{ }
#endif

#define device_create(cls, parent, devt, drvdata, fmt, ...)		\
({									\
	struct device *_dev;						\
	_dev = (device_create)(cls, parent, devt, fmt, __VA_ARGS__);	\
	dev_set_drvdata(_dev, drvdata);					\
	_dev;								\
})

#define dev_name(dev) dev_name((struct device *)dev)

static inline void ethtool_cmd_speed_set(struct ethtool_cmd *ep,
					 __u32 speed)
{
	ep->speed = (__u16)speed;
}

static inline __u32 ethtool_cmd_speed(const struct ethtool_cmd *ep)
{
	return ep->speed;
}

/**
 * lower_32_bits - return bits 0-31 of a number
 * @n: the number we're accessing
 */
#define lower_32_bits(n) ((u32)(n))

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,27)) */

#endif /* LINUX_26_27_COMPAT_H */
