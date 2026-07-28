#ifndef LINUX_26_22_COMPAT_H
#define LINUX_26_22_COMPAT_H

#include <linux/version.h>

/* Compat work for 2.6.21 */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,22))

#include <linux/pci.h>
#include <linux/skbuff.h>

/* reuse ax25_ptr */
#define ieee80211_ptr ax25_ptr

#ifdef CONFIG_AX25
#error Compat reuses the AX.25 pointer so that may not be enabled!
#endif

static inline unsigned char *skb_mac_header(const struct sk_buff *skb)
{
	return skb->mac.raw;
}

static inline void skb_set_mac_header(struct sk_buff *skb, int offset)
{
	skb->mac.raw = skb->data + offset;
}

static inline void skb_reset_mac_header(struct sk_buff *skb)
{
	skb->mac.raw = skb->data;
}

static inline void skb_reset_network_header(struct sk_buff *skb)
{
	skb->nh.raw = skb->data;
}

static inline void skb_set_network_header(struct sk_buff *skb, int offset)
{
	skb->nh.raw = skb->data + offset;
}

static inline void skb_set_transport_header(struct sk_buff *skb, int offset)
{
	skb->h.raw = skb->data + offset;
}

static inline unsigned char *skb_transport_header(struct sk_buff *skb)
{
	return skb->h.raw;
}

static inline unsigned char *skb_network_header(const struct sk_buff *skb)
{
	return skb->nh.raw;
}

static inline unsigned char *skb_tail_pointer(const struct sk_buff *skb)
{
	return skb->tail;
}

static inline struct iphdr *ip_hdr(const struct sk_buff *skb)
{
	return (struct iphdr *)skb_network_header(skb);
}

static inline void skb_copy_from_linear_data(const struct sk_buff *skb,
					     void *to,
					     const unsigned int len)
{
	memcpy(to, skb->data, len);
}

static inline void skb_copy_from_linear_data_offset(const struct sk_buff *skb,
						    const int offset, void *to,
						    const unsigned int len)
{
	memcpy(to, skb->data + offset, len);
}

#define __maybe_unused	__attribute__((unused))

#define uninitialized_var(x) x = x

/* This will lead to very weird behaviour... */
#define NLA_BINARY NLA_STRING

static inline int pci_set_mwi(struct pci_dev *dev)
{
	return -ENOSYS;
}

static inline void pci_clear_mwi(struct pci_dev *dev)
{
}

#define list_first_entry(ptr, type, member) \
        list_entry((ptr)->next, type, member)

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,22)) */

#endif /* LINUX_26_22_COMPAT_H */
