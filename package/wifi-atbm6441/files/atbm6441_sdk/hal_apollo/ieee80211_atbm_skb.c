/*
 * Datapath implementation for altobeam APOLLO mac80211 drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 *Based on apollo code
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <net/atbm_mac80211.h>
#include <linux/etherdevice.h>
#include <linux/skbuff.h>
#include <net/ip.h>
#include <linux/kobject.h>
#include <linux/hash.h>
#include <linux/module.h>

#include "ieee80211_i.h"

#if defined (ATBM_ALLOC_SKB_DEBUG)
#define ATBM_SKB_HASHBITS    16
#define ATBM_SKB_HASHENTRIES (1 << ATBM_SKB_HASHBITS)

#pragma message("Skb Debug Enable")
#define ATBM_SKB_SHOW_BUFF_MAX_SIZE		PAGE_SIZE
#define ATBM_SKB_SHOW_PUT(_show,...)	\
	do{										\
		int ret = 0;						\
		if((_show)->show_count >= (_show)->show_size) break;	\
		ret = scnprintf((_show)->show_buff+(_show)->show_count,(_show)->show_size-(_show)->show_count,__VA_ARGS__);		\
		if(ret>=0)	(_show)->show_count+=ret;				\
	}while(0)

struct ieee80211_atbm_skb_show
{
	char *show_buff;
	int  show_count;
	int  show_size;
};

struct ieee8211_atbm_skb_node{
	struct hlist_node hnode;
	u32 flags;
	const char* call;
	struct sk_buff *skb;
};

static struct hlist_head atbm_skb_hlist[ATBM_SKB_HASHENTRIES];
static unsigned long long skb_n_inserts = 0;
static unsigned long long skb_n_drows = 0;
static spinlock_t ieee80211_atbm_skb_spin_lock;
static struct kobject *atbm_skb_kobj = NULL;
static ssize_t atbm_skb_show(struct kobject *kobj,struct kobj_attribute *attr, char *buf);

static struct kobj_attribute atbm_skb_attr = __ATTR(atbmskb, 0444, atbm_skb_show, NULL);

static struct attribute *atbm_skb_attribute_group[]= {
	&atbm_skb_attr.attr,
	NULL,
};

static struct attribute_group atbm_skb_attr_group = {
	.attrs = atbm_skb_attribute_group,
};

static ssize_t atbm_skb_show(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	struct ieee80211_atbm_skb_show skb_show;
	unsigned long flags;
	struct hlist_head *hlist;
	struct hlist_node *node;
	struct hlist_node *node_temp;
	struct ieee8211_atbm_skb_node *skb_node;
	int hash_index = 0;
	
	skb_show.show_buff = buf;
	skb_show.show_count = 0;
	skb_show.show_size = ATBM_SKB_SHOW_BUFF_MAX_SIZE;

	spin_lock_irqsave(&ieee80211_atbm_skb_spin_lock, flags);
	
	for(hash_index = 0;hash_index<ATBM_SKB_HASHENTRIES;hash_index++){
		hlist = &atbm_skb_hlist[hash_index];
		hlist_for_each_safe(node,node_temp,hlist){
			skb_node = hlist_entry(node,struct ieee8211_atbm_skb_node,hnode);
			ATBM_SKB_SHOW_PUT(&skb_show,"call[%s],skb[%p]\n",skb_node->call,skb_node->skb);
		}
	}
	ATBM_SKB_SHOW_PUT(&skb_show,"n_drows[%lld],n_inserts[%lld]\n",skb_n_drows,skb_n_inserts);
	spin_unlock_irqrestore(&ieee80211_atbm_skb_spin_lock, flags);

	return skb_show.show_count;
}
static int ieee80211_atbm_skb_object_int(void)
{
	int error;

	atbm_skb_kobj = kobject_create_and_add("atbm_skb",
					    atbm_module_parent);
	if (!atbm_skb_kobj)
		return -EINVAL;

	error = sysfs_create_group(atbm_skb_kobj, &atbm_skb_attr_group);
	if (error)
		kobject_put(atbm_skb_kobj);
	return error;
}
static void ieee80211_atbm_skb_object_exit(void)
{
	if(atbm_skb_kobj == NULL)
		return;
	sysfs_remove_group(atbm_skb_kobj, &atbm_skb_attr_group);
	kobject_put(atbm_skb_kobj);
}

void ieee80211_atbm_skb_exit(void)
{
	unsigned long flags;
	struct hlist_head *hlist;
	struct hlist_node *node;
	struct hlist_node *node_temp;
	struct ieee8211_atbm_skb_node *skb_node;
	int hash_index = 0;
	atbm_printk_exit("ieee80211_atbm_skb_exit\n");
	spin_lock_irqsave(&ieee80211_atbm_skb_spin_lock, flags);
	for(hash_index = 0;hash_index<ATBM_SKB_HASHENTRIES;hash_index++){
		hlist = &atbm_skb_hlist[hash_index];
		hlist_for_each_safe(node,node_temp,hlist){
			skb_node = hlist_entry(node,struct ieee8211_atbm_skb_node,hnode);
			atbm_printk_err("%s:call[%s],skb[%p]\n",__func__,skb_node->call,skb_node->skb);
			dev_kfree_skb_any(skb_node->skb);
			atbm_kfree(skb_node);
		}
	}
	spin_unlock_irqrestore(&ieee80211_atbm_skb_spin_lock, flags);
	ieee80211_atbm_skb_object_exit();
}

void ieee80211_atbm_skb_int(void)
{
	spin_lock_init(&ieee80211_atbm_skb_spin_lock);
	atbm_common_hash_list_init(atbm_skb_hlist,ATBM_SKB_HASHENTRIES);
	ieee80211_atbm_skb_object_int();
}

static void ieee80211_atbm_skb_hash_insert(struct sk_buff *skb,const char *func)
{
	int hash_index = 0;
	struct hlist_head *hlist;
	struct hlist_node *node;
	struct ieee8211_atbm_skb_node *skb_node;
	struct ieee8211_atbm_skb_node *skb_node_target = NULL;
	unsigned long flags;
	
	hash_index = atbm_hash_index((u8*)(&skb),sizeof(struct sk_buff *),ATBM_SKB_HASHBITS);

	hlist = &atbm_skb_hlist[hash_index];
	
	spin_lock_irqsave(&ieee80211_atbm_skb_spin_lock, flags);
	
	hlist_for_each(node,hlist){
		skb_node = hlist_entry(node,struct ieee8211_atbm_skb_node,hnode);
		if (skb_node->skb == skb){
			skb_node_target = skb_node;
			break;
		}
	}
	
	if(skb_node_target == NULL){
		
		skb_node_target = atbm_kzalloc(sizeof(struct ieee8211_atbm_skb_node),GFP_ATOMIC);

		if(skb_node_target == NULL){
		}else {
			hlist_add_head(&skb_node_target->hnode,hlist);
			skb_node_target->skb = skb;
			skb_node_target->call = func;
			skb_n_inserts++;
		}
	}
	spin_unlock_irqrestore(&ieee80211_atbm_skb_spin_lock, flags);
}

static void ieee80211_atbm_skb_hash_drow(struct sk_buff *skb)
{
	int hash_index = 0;
	struct hlist_head *hlist;
	struct hlist_node *node;
	struct ieee8211_atbm_skb_node *skb_node;
	struct ieee8211_atbm_skb_node *skb_node_target = NULL;
	unsigned long flags;
	
	hash_index = atbm_hash_index((u8*)(&skb),sizeof(struct sk_buff *),ATBM_SKB_HASHBITS);

	hlist = &atbm_skb_hlist[hash_index];
	
	spin_lock_irqsave(&ieee80211_atbm_skb_spin_lock, flags);
	
	hlist_for_each(node,hlist){
		skb_node = hlist_entry(node,struct ieee8211_atbm_skb_node,hnode);
		if (skb_node->skb == skb){
			skb_node_target = skb_node;
			break;
		}
	}
	
	if(skb_node_target){
		hlist_del(&skb_node_target->hnode);
		atbm_kfree(skb_node_target);
		skb_n_drows ++;
	}
	spin_unlock_irqrestore(&ieee80211_atbm_skb_spin_lock, flags);
}

void ieee80211_atbm_add_skb_to_debug_list(struct sk_buff *skb,const char *func)
{
	ieee80211_atbm_skb_hash_insert(skb,func);
}

void ieee80211_atbm_rx_debug_setflag(struct sk_buff *skb,u32 flags)
{

}

void ieee80211_atbm_rx_debug_setflag2(struct sk_buff *skb,u16 fc)
{
	
}


struct sk_buff *__ieee80211_atbm_dev_alloc_skb(unsigned int length,gfp_t gfp_mask,const char *func)
{
	struct sk_buff * atbm_skb = NULL;
	
	atbm_skb = __dev_alloc_skb(length,gfp_mask);

	if(atbm_skb == NULL){
		return atbm_skb;
	}
	ieee80211_atbm_skb_hash_insert(atbm_skb,func);
	return atbm_skb;
}

struct sk_buff *ieee80211_atbm_dev_alloc_skb(unsigned int length,const char *func)
{
	struct sk_buff * atbm_skb = NULL;
	
	atbm_skb = dev_alloc_skb(length);

	if(atbm_skb == NULL){
		return atbm_skb;
	}
	
	ieee80211_atbm_skb_hash_insert(atbm_skb,func);
	return atbm_skb;
}
struct sk_buff *ieee80211_atbm_alloc_skb(unsigned int size,gfp_t priority,const char *func)
{
	struct sk_buff * atbm_skb = NULL;
	atbm_skb = alloc_skb(size,priority);

	if(atbm_skb){
		ieee80211_atbm_skb_hash_insert(atbm_skb,func);
	}

	return atbm_skb;
}
void ieee80211_atbm_dev_kfree_skb_any(struct sk_buff *skb)
{
	ieee80211_atbm_skb_hash_drow(skb);
	dev_kfree_skb_any(skb);
}

void ieee80211_atbm_dev_kfree_skb(struct sk_buff *skb)
{	
	if(!skb){
		return;
	}
	ieee80211_atbm_skb_hash_drow(skb);
	dev_kfree_skb(skb);
}

void ieee80211_atbm_kfree_skb(struct sk_buff *skb)
{
	if(!skb){
		return;
	}
	ieee80211_atbm_skb_hash_drow(skb);
	kfree_skb(skb);
}
void ieee80211_atbm_dev_kfree_skb_irq(struct sk_buff *skb)
{
	if(!skb){
		return;
	}
	ieee80211_atbm_skb_hash_drow(skb);
	dev_kfree_skb_irq(skb);
}

void ieee80211_atbm_skb_reserve(struct sk_buff *skb, int len)
{
	skb_reserve(skb,len);
}

void ieee80211_atbm_skb_trim(struct sk_buff *skb, unsigned int len)
{
	skb_trim(skb,len);
}

unsigned char *ieee80211_atbm_skb_put(struct sk_buff *skb, unsigned int len)
{
	return skb_put(skb,len);
}

void ieee80211_atbm_skb_queue_tail(struct sk_buff_head *list, struct sk_buff *newsk)
{
	skb_queue_tail(list,newsk);
}
struct sk_buff *__ieee80211_atbm_skb_dequeue(struct sk_buff_head *list)
{
	struct sk_buff * skb = __skb_dequeue(list);
	return skb;
}

struct sk_buff *ieee80211_atbm_skb_dequeue(struct sk_buff_head *list)
{
	struct sk_buff * skb = skb_dequeue(list);
	return skb;
}

void __ieee80211_atbm_skb_queue_purge(struct sk_buff_head *list)
{
	struct sk_buff *skb;
	while ((skb = __ieee80211_atbm_skb_dequeue(list)) != NULL)
		ieee80211_atbm_kfree_skb(skb);
}

void ieee80211_atbm_skb_queue_purge(struct sk_buff_head *list)
{
	struct sk_buff *skb;
	while ((skb = ieee80211_atbm_skb_dequeue(list)) != NULL){
		ieee80211_atbm_kfree_skb(skb);
	}
}

int ieee80211_atbm_skb_tailroom(const struct sk_buff *skb)
{
	return skb_tailroom(skb);
}

int ieee80211_atbm_skb_queue_empty(const struct sk_buff_head *list)
{
	return skb_queue_empty(list);
}

void ieee80211_atbm_skb_queue_splice_tail_init(struct sk_buff_head *list,
					      struct sk_buff_head *head)
{
	skb_queue_splice_tail_init(list,head);
}

void ieee80211_atbm_skb_queue_head_init(struct sk_buff_head *list)
{
	skb_queue_head_init(list);
}

void __ieee80211_atbm_skb_queue_tail(struct sk_buff_head *list,struct sk_buff *newsk,const char *func)
{
	__skb_queue_tail(list,newsk);
}

__u32 ieee80211_atbm_skb_queue_len(const struct sk_buff_head *list_)
{
	return skb_queue_len(list_);
}

void __ieee80211_atbm_skb_queue_head_init(struct sk_buff_head *list)
{
	__skb_queue_head_init(list);
}
void __ieee80211_atbm_skb_queue_head(struct sk_buff_head *list,
				    struct sk_buff *newsk)
{
	__skb_queue_head(list,newsk);
}
struct sk_buff *ieee80211_atbm_skb_copy(const struct sk_buff *skb, gfp_t gfp_mask,const char *func)
{
	struct sk_buff *new_skb = NULL;
	
	new_skb = skb_copy(skb,gfp_mask);

	if(new_skb)
		ieee80211_atbm_skb_hash_insert(new_skb,func);

	return new_skb;
	
}
unsigned char *ieee80211_atbm_skb_pull(struct sk_buff *skb, unsigned int len)
{
	return skb_pull(skb,len);
}

unsigned char *ieee80211_atbm_skb_push(struct sk_buff *skb, unsigned int len)
{
	char *p;
	p = skb_push(skb,len);
	return p;
}
int ieee80211_atbm_dev_queue_xmit(struct sk_buff *skb)
{
	ieee80211_atbm_skb_hash_drow(skb);
		
	return dev_queue_xmit(skb);
}

int ieee80211_atbm_netif_rx_ni(struct sk_buff *skb)
{
	ieee80211_atbm_skb_hash_drow(skb);
	return netif_rx_ni(skb);
}
void ieee80211_atbm_skb_set_queue_mapping(struct sk_buff *skb, u16 queue_mapping)
{
	skb_set_queue_mapping(skb,queue_mapping);
}

void ieee80211_atbm_skb_set_tail_pointer(struct sk_buff *skb, const int offset)
{
	skb_set_tail_pointer(skb,offset);
}
void ieee80211_atbm_skb_reset_tail_pointer(struct sk_buff *skb)
{
	skb_reset_tail_pointer(skb);
}
void __ieee80211_atbm_skb_unlink(struct sk_buff *skb, struct sk_buff_head *list)
{
	__skb_unlink(skb,list);
}

void ieee80211_atbm_skb_set_mac_header(struct sk_buff *skb, const int offset)
{
	skb_set_mac_header(skb,offset);
}
void ieee80211_atbm_skb_set_network_header(struct sk_buff *skb, int offset)
{
	skb_set_network_header(skb,offset);
}

void ieee80211_atbm_skb_set_transport_header(struct sk_buff *skb, int offset)
{
	skb_set_transport_header(skb,offset);
}

void ieee80211_atbm_skb_queue_splice(const struct sk_buff_head *list,
				    struct sk_buff_head *head)
{
	skb_queue_splice(list,head);
}

void ieee80211_atbm_skb_queue_splice_init(struct sk_buff_head *list,
					 struct sk_buff_head *head)
{
	skb_queue_splice_init(list,head);
}

int __ieee80211_atbm_pskb_trim(struct sk_buff *skb, unsigned int len)
{
	return __pskb_trim(skb,len);
}

int ieee80211_atbm_pskb_may_pull(struct sk_buff *skb, unsigned int len)
{
	return pskb_may_pull(skb,len);
}
unsigned int ieee80211_atbm_skb_headroom(const struct sk_buff *skb)
{
	return skb_headroom(skb);
}
int ieee80211_atbm_pskb_expand_head(struct sk_buff *skb, int nhead, int ntail,
		     gfp_t gfp_mask,const char *func)
{
	int ret = 0;
	ret = pskb_expand_head(skb,nhead,ntail,gfp_mask);
	return ret;
}

struct sk_buff *ieee80211_atbm_skb_copy_expand(const struct sk_buff *skb,
				int newheadroom, int newtailroom,
				gfp_t gfp_mask,const char *func)
{
	struct sk_buff *skb_copy = NULL;
	
	skb_copy = skb_copy_expand(skb,newheadroom,newtailroom,gfp_mask);

	if(skb_copy){
		ieee80211_atbm_skb_hash_insert(skb_copy,func);
	}

	return skb_copy;
	
}
int ieee80211_atbm_skb_cloned(const struct sk_buff *skb)
{
	return skb_cloned(skb);
}
struct sk_buff *ieee80211_atbm_skb_clone(struct sk_buff *skb, gfp_t gfp_mask,const char *func)
{
	struct sk_buff *cloned_skb = NULL;

	cloned_skb = skb_clone(skb,gfp_mask);

	if(cloned_skb){		
		ieee80211_atbm_skb_hash_insert(cloned_skb,func);
	}

	return cloned_skb;
}
int ieee80211_atbm_netif_rx(struct sk_buff *skb)
{	
	ieee80211_atbm_skb_hash_drow(skb);
	return netif_rx(skb);
}
int ieee80211_atbm_netif_receive_skb(struct sk_buff *skb)
{	
	ieee80211_atbm_skb_hash_drow(skb);
	return netif_receive_skb(skb);
}
int ieee80211_atbm_skb_linearize(struct sk_buff *skb)
{
	return skb_linearize(skb);
}

struct sk_buff *ieee80211_atbm_skb_peek(struct sk_buff_head *list_)
{
	return skb_peek(list_);
}

int ieee80211_atbm_skb_shared(const struct sk_buff *skb)
{
	return skb_shared(skb);
}

int ieee80211_atbm_skb_padto(struct sk_buff *skb, unsigned int len)
{
	return skb_padto(skb,len);
}

struct sk_buff *ieee80211_atbm_skb_get(struct sk_buff *skb)
{
	return skb_get(skb);
}
void ieee80211_atbm_skb_orphan(struct sk_buff *skb,const char *func)
{
	skb_orphan(skb);
}
void ieee80211_atbm_amsdu_to_8023s(struct sk_buff *skb, struct sk_buff_head *list,
			      const u8 *addr, enum nl80211_iftype iftype,
			      const unsigned int extra_headroom,
			      bool has_80211_header)
{
	struct sk_buff *frame = NULL;
	u16 ethertype;
	u8 *payload;
	const struct ethhdr *eth;
	int remaining, err;
	u8 dst[ETH_ALEN], src[ETH_ALEN];

	if (has_80211_header) {
		err = ieee80211_data_to_8023(skb, addr, iftype);
		if (err)
			goto out;

		/* skip the wrapping header */
		eth = (struct ethhdr *) ieee80211_atbm_skb_pull(skb, sizeof(struct ethhdr));
		if (!eth)
			goto out;
	} else {
		eth = (struct ethhdr *) skb->data;
	}

	while (skb != frame) {
		u8 padding;
		__be16 len = eth->h_proto;
		unsigned int subframe_len = sizeof(struct ethhdr) + ntohs(len);

		remaining = skb->len;
		memcpy(dst, eth->h_dest, ETH_ALEN);
		memcpy(src, eth->h_source, ETH_ALEN);

		padding = (4 - subframe_len) & 0x3;
		/* the last MSDU has no padding */
		if (subframe_len > remaining)
			goto purge;

		ieee80211_atbm_skb_pull(skb, sizeof(struct ethhdr));
		/* reuse skb for the last subframe */
		if (remaining <= subframe_len + padding)
			frame = skb;
		else {
			unsigned int hlen = ALIGN(extra_headroom, 4);
			/*
			 * Allocate and reserve two bytes more for payload
			 * alignment since sizeof(struct ethhdr) is 14.
			 */
			frame = ieee80211_atbm_dev_alloc_skb(hlen + subframe_len + 2,__func__);
			if (!frame)
				goto purge;

			ieee80211_atbm_skb_reserve(frame, hlen + sizeof(struct ethhdr) + 2);
			memcpy(ieee80211_atbm_skb_put(frame, ntohs(len)), skb->data,
				ntohs(len));

			eth = (struct ethhdr *)ieee80211_atbm_skb_pull(skb, ntohs(len) +
							padding);
			if (!eth) {
				ieee80211_atbm_dev_kfree_skb(frame);
				goto purge;
			}
		}

		skb_reset_network_header(frame);
		frame->dev = skb->dev;
		frame->priority = skb->priority;

		payload = frame->data;
		ethertype = (payload[6] << 8) | payload[7];

		if (likely((ether_addr_equal(payload, rfc1042_header) &&
			    ethertype != ETH_P_AARP && ethertype != ETH_P_IPX) ||
			   ether_addr_equal(payload, bridge_tunnel_header))) {
			/* remove RFC1042 or Bridge-Tunnel
			 * encapsulation and replace EtherType */
			ieee80211_atbm_skb_pull(frame, 6);
			memcpy(ieee80211_atbm_skb_push(frame, ETH_ALEN), src, ETH_ALEN);
			memcpy(ieee80211_atbm_skb_push(frame, ETH_ALEN), dst, ETH_ALEN);
		} else {
			memcpy(ieee80211_atbm_skb_push(frame, sizeof(__be16)), &len,
				sizeof(__be16));
			memcpy(ieee80211_atbm_skb_push(frame, ETH_ALEN), src, ETH_ALEN);
			memcpy(ieee80211_atbm_skb_push(frame, ETH_ALEN), dst, ETH_ALEN);
		}
		__ieee80211_atbm_skb_queue_tail(list, frame,__func__);
	}

	return;

 purge:
	__ieee80211_atbm_skb_queue_purge(list);
 out:
	ieee80211_atbm_dev_kfree_skb(skb);
}

#endif
