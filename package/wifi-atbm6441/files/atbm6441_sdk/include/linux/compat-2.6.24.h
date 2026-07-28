#ifndef LINUX_26_24_COMPAT_H
#define LINUX_26_24_COMPAT_H

#include <linux/version.h>

/* Compat work for 2.6.21, 2.6.22 and 2.6.23 */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,24))

#include <asm/atomic.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/usb.h>
#include <linux/types.h>
#include <linux/list.h>
#include <linux/scatterlist.h>

#define KEY_BLUETOOTH	237
#define KEY_WLAN	238
#define KEY_UWB		239

#define DMA_BIT_MASK(n) (((n) == 64) ? ~0ULL : ((1ULL<<(n))-1))

struct proc_dir_entry;
struct net_device;
struct net {
	atomic_t		count;		/* To decided when the network
						 *  namespace should be freed.
						 */
	atomic_t		use_count;	/* To track references we
						 * destroy on demand
						 */
	struct list_head	list;		/* list of network namespaces */
	struct work_struct	work;		/* work struct for freeing */

	struct proc_dir_entry 	*proc_net;
	struct proc_dir_entry 	*proc_net_stat;
	struct proc_dir_entry 	*proc_net_root;

	struct net_device       *loopback_dev;          /* The loopback */

	struct list_head 	dev_base_head;
	struct hlist_head 	*dev_name_head;
	struct hlist_head	*dev_index_head;
};

#ifdef CONFIG_NET
/* Init's network namespace */
extern struct net init_net;
#define INIT_NET_NS(net_ns) .net_ns = &init_net,
#else
#define INIT_NET_NS(net_ns)
#endif

/* Added on 2.6.24 in include/linux/types.h by Al viro on commit 142956af */
typedef unsigned long               uintptr_t;

/* From include/linux/net.h */
enum sock_shutdown_cmd {
	SHUT_RD		= 0,
	SHUT_WR		= 1,
	SHUT_RDWR	= 2,
};

#if (LINUX_VERSION_CODE == KERNEL_VERSION(2,6,23)) /* Local check */
/* Added as of 2.6.24 in include/linux/skbuff.h.
 *
 * Although 2.6.23 does support for CONFIG_NETDEVICES_MULTIQUEUE
 * this helper was not added until 2.6.24. This implementation
 * is exactly as it is on newer kernels.
 *
 * For older kernels we use the an internal mac80211 hack.
 * For details see changes to include/net/atbm_mac80211.h through
 * compat.diff and compat/mq_compat.h */
static inline u16 skb_get_queue_mapping(struct sk_buff *skb)
{
#ifdef CONFIG_NETDEVICES_MULTIQUEUE
	return skb->queue_mapping;
#else
	return 0;
#endif
}
#endif /* Local 2.6.23 check */

/* On older kernels we handle this a bit differently, so we yield to that
 * code for its implementation in mq_compat.h as we want to make
 * use of the internal mac80211 __ieee80211_queue_stopped() which itself
 * uses internal mac80211 data structure hacks. */
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,23)) /* Local check */
/**
 * netif_subqueue_stopped - test status of subqueue
 * @dev: network device
 * @queue_index: sub queue index
 *
 * Check individual transmit queue of a device with multiple transmit queues.
 */
static inline int __netif_subqueue_stopped(const struct net_device *dev,
					u16 queue_index)
{
#ifdef CONFIG_NETDEVICES_MULTIQUEUE
	return test_bit(__LINK_STATE_XOFF,
	&dev->egress_subqueue[queue_index].state);
#else
	return 0;
#endif
}

/* Note: although the backport implementation for netif_subqueue_stopped
 * on older kernels is identical to upstream __netif_subqueue_stopped()
 * (except for a const qualifier) we implement netif_subqueue_stopped()
 * as part of mac80211 as it relies on internal mac80211 structures we
 * use for MQ support. We this implement it in mq_compat.h */

#endif /* Local 2.6.23 check */

/*
 * Force link bug if constructor is used, can't be done compatibly
 * because constructor arguments were swapped since then!
 */
extern void __incompatible_kmem_cache_create(void);

/* 2.6.21 and 2.6.22 kmem_cache_create() takes 6 arguments */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,23))
#define kmem_cache_create(name, objsize, align, flags, ctor) 	\
	({							\
		if (ctor) __incompatible_kmem_cache_create();	\
		kmem_cache_create((name), (objsize), (align),	\
				  (flags), NULL, NULL);		\
	})
#endif

/* 2.6.23 kmem_cache_create() takes 5 arguments */
#if (LINUX_VERSION_CODE == KERNEL_VERSION(2,6,23))
#define kmem_cache_create(name, objsize, align, flags, ctor) 	\
	({							\
		if (ctor) __incompatible_kmem_cache_create();	\
		kmem_cache_create((name), (objsize), (align),	\
				  (flags), NULL);		\
	})
#endif

/* From include/linux/mod_devicetable.h */

/* SSB core, see drivers/ssb/ */
#ifndef SSB_DEVICE
struct ssb_device_id {
	__u16   vendor;
	__u16   coreid;
	__u8    revision;
};
#define SSB_DEVICE(_vendor, _coreid, _revision)  \
	{ .vendor = _vendor, .coreid = _coreid, .revision = _revision, }
#define SSB_DEVTABLE_END  \
	{ 0, },

#define SSB_ANY_VENDOR          0xFFFF
#define SSB_ANY_ID              0xFFFF
#define SSB_ANY_REV             0xFF
#endif


/* Namespace stuff, introduced on 2.6.24 */
#define dev_get_by_index(a, b)		dev_get_by_index(b)
#define __dev_get_by_index(a, b)	__dev_get_by_index(b)

extern int		eth_header(struct sk_buff *skb, struct net_device *dev,
				unsigned short type, void *daddr,
				void *saddr, unsigned len);
extern int		eth_rebuild_header(struct sk_buff *skb);
extern void		eth_header_cache_update(struct hh_cache *hh, struct net_device *dev,
				unsigned char * haddr);
extern int		eth_header_cache(struct neighbour *neigh,
			struct hh_cache *hh);

/* This structure is simply not present on 2.6.22 and 2.6.23 */
struct header_ops {
	int     (*create) (struct sk_buff *skb, struct net_device *dev,
		unsigned short type, void *daddr,
		void *saddr, unsigned len);
	int     (*parse)(const struct sk_buff *skb, unsigned char *haddr);
	int     (*rebuild)(struct sk_buff *skb);
	#define HAVE_HEADER_CACHE
	int     (*cache)(struct neighbour *neigh, struct hh_cache *hh);
	void    (*cache_update)(struct hh_cache *hh,
		struct net_device *dev,
		unsigned char *haddr);
};

/* net/ieee80211/ieee80211_crypt_tkip uses sg_init_table. This was added on
 * 2.6.24. CONFIG_DEBUG_SG was added in 2.6.24 as well, so lets just ignore
 * the debug stuff. Note that adding this required changes to the struct
 * scatterlist on include/asm/scatterlist*, so the right way to port this
 * is to simply ignore the new structure changes and zero the scatterlist
 * array. We lave the kdoc intact for reference.
 */

/**
 * sg_mark_end - Mark the end of the scatterlist
 * @sg:          SG entryScatterlist
 *
 * Description:
 *   Marks the passed in sg entry as the termination point for the sg
 *   table. A call to sg_next() on this entry will return NULL.
 *
 **/
static inline void sg_mark_end(struct scatterlist *sg)
{
#ifdef CONFIG_DEBUG_SG
	BUG_ON(sg->sg_magic != SG_MAGIC);
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,24))
	/*
	 * Set termination bit, clear potential chain bit
	*/
	sg->page_link |= 0x02;
	sg->page_link &= ~0x01;
#endif
}

/**
 * sg_init_table - Initialize SG table
 * @sgl:           The SG table
 * @nents:         Number of entries in table
 *
 * Notes:
 *   If this is part of a chained sg table, sg_mark_end() should be
 *   used only on the last table part.
 *
 **/
static inline void sg_init_table(struct scatterlist *sgl, unsigned int nents)
{
	memset(sgl, 0, sizeof(*sgl) * nents);
}

/**
 * usb_endpoint_num - get the endpoint's number
 * @epd: endpoint to be checked
 *
 * Returns @epd's number: 0 to 15.
 */
static inline int usb_endpoint_num(const struct usb_endpoint_descriptor *epd)
{
	return epd->bEndpointAddress & USB_ENDPOINT_NUMBER_MASK;
}

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,24)) */

#endif /* LINUX_26_24_COMPAT_H */
