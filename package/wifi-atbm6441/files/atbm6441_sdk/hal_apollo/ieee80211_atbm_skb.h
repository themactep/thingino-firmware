#ifndef _IEEE80211_ATBM_SKB_H_
#define _IEEE80211_ATBM_SKB_H_
#if defined (ATBM_ALLOC_SKB_DEBUG)
extern void ieee80211_atbm_add_skb_to_debug_list(struct sk_buff *skb,const char *func);

extern void ieee80211_atbm_skb_exit(void);

extern void ieee80211_atbm_skb_int(void);
extern struct sk_buff *ieee80211_atbm_dev_alloc_skb(unsigned int length,const char *func);
extern struct sk_buff *__ieee80211_atbm_dev_alloc_skb(unsigned int length,gfp_t gfp_mask,const char *func);
struct sk_buff *ieee80211_atbm_alloc_skb(unsigned int size,gfp_t priority,const char *func);
extern void ieee80211_atbm_dev_kfree_skb_any(struct sk_buff *skb);
extern void ieee80211_atbm_dev_kfree_skb(struct sk_buff *skb);
extern void ieee80211_atbm_kfree_skb(struct sk_buff *skb);
extern void ieee80211_atbm_dev_kfree_skb_irq(struct sk_buff *skb);
extern void ieee80211_atbm_skb_reserve(struct sk_buff *skb, int len);
extern void ieee80211_atbm_skb_trim(struct sk_buff *skb, unsigned int len);
extern unsigned char *ieee80211_atbm_skb_put(struct sk_buff *skb, unsigned int len);
extern void ieee80211_atbm_skb_queue_tail(struct sk_buff_head *list, struct sk_buff *newsk);
extern struct sk_buff *__ieee80211_atbm_skb_dequeue(struct sk_buff_head *list);
extern struct sk_buff *ieee80211_atbm_skb_dequeue(struct sk_buff_head *list);
extern void __ieee80211_atbm_skb_queue_purge(struct sk_buff_head *list);
extern void ieee80211_atbm_skb_queue_purge(struct sk_buff_head *list);
extern int ieee80211_atbm_skb_tailroom(const struct sk_buff *skb);
extern int ieee80211_atbm_skb_queue_empty(const struct sk_buff_head *list);
extern void ieee80211_atbm_skb_queue_splice_tail_init(struct sk_buff_head *list,
					      struct sk_buff_head *head);
extern void ieee80211_atbm_skb_queue_head_init(struct sk_buff_head *list);

extern void __ieee80211_atbm_skb_queue_tail(struct sk_buff_head *list,struct sk_buff *newsk,const char *func);

extern __u32 ieee80211_atbm_skb_queue_len(const struct sk_buff_head *list_);

extern void __ieee80211_atbm_skb_queue_head_init(struct sk_buff_head *list);
extern void __ieee80211_atbm_skb_queue_head(struct sk_buff_head *list,
				    struct sk_buff *newsk);
extern struct sk_buff *ieee80211_atbm_skb_copy(const struct sk_buff *skb, gfp_t gfp_mask,const char *func);
extern unsigned char *ieee80211_atbm_skb_pull(struct sk_buff *skb, unsigned int len);
extern unsigned char *ieee80211_atbm_skb_push(struct sk_buff *skb, unsigned int len);
extern int ieee80211_atbm_netif_rx_ni(struct sk_buff *skb);
extern void ieee80211_atbm_skb_set_queue_mapping(struct sk_buff *skb, u16 queue_mapping);
extern void ieee80211_atbm_skb_set_tail_pointer(struct sk_buff *skb, const int offset);
extern void ieee80211_atbm_skb_reset_tail_pointer(struct sk_buff *skb);
extern void __ieee80211_atbm_skb_unlink(struct sk_buff *skb, struct sk_buff_head *list);
extern void ieee80211_atbm_skb_set_mac_header(struct sk_buff *skb, const int offset);
extern void ieee80211_atbm_skb_set_network_header(struct sk_buff *skb, int offset);

extern void ieee80211_atbm_skb_set_transport_header(struct sk_buff *skb, int offset);

extern void ieee80211_atbm_skb_queue_splice(const struct sk_buff_head *list,
				    struct sk_buff_head *head);
extern void ieee80211_atbm_skb_queue_splice_init(struct sk_buff_head *list,
					 struct sk_buff_head *head);
extern int __ieee80211_atbm_pskb_trim(struct sk_buff *skb, unsigned int len);
extern int ieee80211_atbm_pskb_may_pull(struct sk_buff *skb, unsigned int len);
extern unsigned int ieee80211_atbm_skb_headroom(const struct sk_buff *skb);
extern int ieee80211_atbm_pskb_expand_head(struct sk_buff *skb, int nhead, int ntail,
		     gfp_t gfp_mask,const char *func);
extern struct sk_buff *ieee80211_atbm_skb_copy_expand(const struct sk_buff *skb,
				int newheadroom, int newtailroom,
				gfp_t gfp_mask,const char *func);
extern  int ieee80211_atbm_skb_cloned(const struct sk_buff *skb);
extern struct sk_buff *ieee80211_atbm_skb_clone(struct sk_buff *skb, gfp_t gfp_mask,const char *func);
extern int ieee80211_atbm_netif_receive_skb(struct sk_buff *skb);
extern int ieee80211_atbm_dev_queue_xmit(struct sk_buff *skb);
extern int ieee80211_atbm_skb_linearize(struct sk_buff *skb);
extern struct sk_buff *ieee80211_atbm_skb_peek(struct sk_buff_head *list_);

extern int ieee80211_atbm_skb_shared(const struct sk_buff *skb);

extern int ieee80211_atbm_skb_padto(struct sk_buff *skb, unsigned int len);
extern int ieee80211_atbm_netif_rx(struct sk_buff *skb);
extern struct sk_buff *ieee80211_atbm_skb_get(struct sk_buff *skb);
extern void ieee80211_atbm_rx_debug_setflag(struct sk_buff *skb,u32 flags);
extern void ieee80211_atbm_rx_debug_setflag2(struct sk_buff *skb,u16 fc);
extern void ieee80211_atbm_amsdu_to_8023s(struct sk_buff *skb, struct sk_buff_head *list,
			      const u8 *addr, enum nl80211_iftype iftype,
			      const unsigned int extra_headroom,
			      bool has_80211_header);
extern void ieee80211_atbm_skb_orphan(struct sk_buff *skb,const char *func);


#define RX_DEBUG_FLAG_MAC   BIT(1)
#define RX_DEBUG_FLAG_HAL   BIT(0)
#define RX_DEBUG_FLAG_MULTI   BIT(2)
#define RX_DEBUG_FLAG_DATA   BIT(3)
#define RX_DEBUG_FLAG_AP   BIT(4)
#define RX_DEBUG_FLAG_SOFTLINK   BIT(5)
#define RX_DEBUG_FLAG_IRQRXMAC   BIT(6)
#define RX_DEBUG_FLAG_MAC_RX1   BIT(7)
#define RX_DEBUG_FLAG_MAC_RX2   BIT(8)
#define RX_DEBUG_FLAG_MAC_RX3   BIT(9)
#define RX_DEBUG_FLAG_MAC_RX4   BIT(10)
#define RX_DEBUG_FLAG_CTRL   BIT(11)
#define RX_DEBUG_FLAG_WORK   BIT(12)
#define RX_DEBUG_FLAG_ADDWORK   BIT(13)

struct ieee80211_atbm_skb_hdr
{
	struct list_head head;
	const char *call_addr;
	long masker;
	u32 flags;
	u32 generation;
	u32 truesize;
	u8 mem[0] __attribute__((__aligned__(64)));
};

#define IEEE80211_ATBM_SKB_HEAD_SIZE sizeof(struct ieee80211_atbm_skb_hdr)
#define __atbm_dev_alloc_skb(_length,_gfp_mask) 				__ieee80211_atbm_dev_alloc_skb(_length,_gfp_mask,__func__)																														
#define atbm_dev_alloc_skb(_length)								ieee80211_atbm_dev_alloc_skb(_length,__func__)              																														    
#define atbm_alloc_skb(_size,_priority) 						ieee80211_atbm_alloc_skb(_size,_priority,__func__)      																														
#define atbm_dev_kfree_skb_any(_skb)							ieee80211_atbm_dev_kfree_skb_any(_skb)																														
#define atbm_dev_kfree_skb(_skb)								ieee80211_atbm_dev_kfree_skb(_skb)																														
#define atbm_kfree_skb(_skb)									ieee80211_atbm_kfree_skb(_skb)																														
#define atbm_dev_kfree_skb_irq(_skb)							ieee80211_atbm_dev_kfree_skb_irq(_skb)																														
#define atbm_skb_reserve(_skb,_len)								ieee80211_atbm_skb_reserve(_skb,_len)																														
#define atbm_skb_trim(_skb, _len)								ieee80211_atbm_skb_trim(_skb, _len)
#define atbm_skb_put(_skb,_len)									ieee80211_atbm_skb_put(_skb,_len)
#define atbm_skb_queue_tail(_list,_newsk)						ieee80211_atbm_skb_queue_tail(_list,_newsk)
#define __atbm_skb_dequeue(_list)								__ieee80211_atbm_skb_dequeue(_list)
#define atbm_skb_dequeue(_list)									ieee80211_atbm_skb_dequeue(_list)
#define __atbm_skb_queue_purge(_list)							__ieee80211_atbm_skb_queue_purge(_list)
#define atbm_skb_queue_purge(_list)								ieee80211_atbm_skb_queue_purge(_list)
#define atbm_skb_tailroom(_skb)									ieee80211_atbm_skb_tailroom(_skb)
#define atbm_skb_queue_empty(_list)								ieee80211_atbm_skb_queue_empty(_list)
#define atbm_skb_queue_splice_tail_init(_list,_head)			ieee80211_atbm_skb_queue_splice_tail_init(_list,_head)
#define atbm_skb_queue_head_init(_list)							ieee80211_atbm_skb_queue_head_init(_list)
#define __atbm_skb_queue_tail(_list,_newsk)						__ieee80211_atbm_skb_queue_tail(_list,_newsk,__func__)
#define atbm_skb_queue_len(_list_)								ieee80211_atbm_skb_queue_len(_list_)
#define __atbm_skb_queue_head_init(_list)						__ieee80211_atbm_skb_queue_head_init(_list)
#define __atbm_skb_queue_head(_list,_newsk)						__ieee80211_atbm_skb_queue_head(_list,_newsk)
#define atbm_skb_copy(_skb,_gfp_mask)							ieee80211_atbm_skb_copy(_skb,_gfp_mask,__func__)
#define atbm_skb_pull(_skb,_len)								ieee80211_atbm_skb_pull(_skb,_len)
#define atbm_skb_push(_skb,_len)								ieee80211_atbm_skb_push(_skb,_len)
#define atbm_netif_rx_ni(_skb)									ieee80211_atbm_netif_rx_ni(_skb)
#define atbm_skb_set_queue_mapping(_skb,_queue_mapping)			ieee80211_atbm_skb_set_queue_mapping(_skb,_queue_mapping)
#define atbm_skb_set_tail_pointer(_skb,_offset)					ieee80211_atbm_skb_set_tail_pointer(_skb,_offset)
#define atbm_skb_reset_tail_pointer(_skb)						ieee80211_atbm_skb_reset_tail_pointer(_skb)
#define __atbm_skb_unlink(_skb,_list)							__ieee80211_atbm_skb_unlink(_skb,_list)
#define atbm_skb_set_mac_header(_skb,_offset)					ieee80211_atbm_skb_set_mac_header(_skb,_offset)
#define atbm_skb_set_network_header(_skb,_offset)				ieee80211_atbm_skb_set_network_header(_skb,_offset)
#define atbm_skb_set_transport_header(_skb,_offset)				ieee80211_atbm_skb_set_transport_header(_skb,_offset)
#define atbm_skb_queue_splice(_list,_head)						ieee80211_atbm_skb_queue_splice(_list,_head)
#define atbm_skb_queue_splice_init(_list,_head)					ieee80211_atbm_skb_queue_splice_init(_list,_head)
#define __atbm_pskb_trim(_skb,_len)								__ieee80211_atbm_pskb_trim(_skb,_len)
#define atbm_pskb_may_pull(_skb,_len)							ieee80211_atbm_pskb_may_pull(_skb,_len)																	
#define atbm_skb_headroom(_skb)									ieee80211_atbm_skb_headroom(_skb)
#define atbm_pskb_expand_head(_skb,_nhead,_ntail,_gfp_mask)		ieee80211_atbm_pskb_expand_head(_skb,_nhead,_ntail,_gfp_mask,__func__)
#define atbm_skb_copy_expand(_skb,_newheadroom,_newtailroom,_gfp_mask)	\
				ieee80211_atbm_skb_copy_expand(_skb,_newheadroom,_newtailroom,_gfp_mask,__func__)
#define atbm_skb_cloned(_skb)									ieee80211_atbm_skb_cloned(_skb)
#define atbm_skb_clone(_skb,_gfp_mask)							ieee80211_atbm_skb_clone(_skb,_gfp_mask,__func__)
#define atbm_netif_receive_skb(_skb)							ieee80211_atbm_netif_receive_skb(_skb)
#define atbm_netif_rx(_skb)										ieee80211_atbm_netif_rx(_skb)
#define atbm_dev_queue_xmit(_skb)								ieee80211_atbm_dev_queue_xmit(_skb)
#define atbm_skb_linearize(_skb)								ieee80211_atbm_skb_linearize(_skb)
#define atbm_skb_peek(_list_)									ieee80211_atbm_skb_peek(_list_)
#define atbm_skb_shared(_skb)									ieee80211_atbm_skb_shared(_skb)
#define atbm_skb_padto(_skb,_len)  								ieee80211_atbm_skb_padto(_skb,_len)
#define atbm_skb_tx_debug(_skb)									ieee80211_atbm_add_skb_to_debug_list(_skb,__func__)
#define atbm_skb_get(_skb)										ieee80211_atbm_skb_get(_skb)
#define atbm_skb_rx_debug(_skb,_f)								ieee80211_atbm_rx_debug_setflag(_skb,_f)
#define atbm_skb_rx_debug2(_skb,_fc)							ieee80211_atbm_rx_debug_setflag2(_skb,_fc)
#define atbm_amsdu_to_8023s(_skb, _list,_addr,_iftype,_extra_headroom)		\
		ieee80211_atbm_amsdu_to_8023s(_skb, _list,_addr,_iftype,_extra_headroom,true)
#define atbm_skb_orphan(_skb)									ieee80211_atbm_skb_orphan(_skb,__func__)
#else
#define __atbm_dev_alloc_skb(_length,_gfp_mask) 				__dev_alloc_skb(_length,_gfp_mask)																														
#define atbm_dev_alloc_skb(_length)								dev_alloc_skb(_length)              																														    
#define atbm_alloc_skb(_size,_priority) 						alloc_skb(_size,_priority)      																														
#define atbm_dev_kfree_skb_any(_skb)							dev_kfree_skb_any(_skb)																														
#define atbm_dev_kfree_skb(_skb)								dev_kfree_skb(_skb)																														
#define atbm_kfree_skb(_skb)									kfree_skb(_skb)																														
#define atbm_dev_kfree_skb_irq(_skb)							dev_kfree_skb_irq(_skb)																														
#define atbm_skb_reserve(_skb,_len)								skb_reserve(_skb,_len)																														
#define atbm_skb_trim(_skb, _len)								skb_trim(_skb, _len)
#define atbm_skb_put(_skb,_len)									skb_put(_skb,_len)
#define atbm_skb_queue_tail(_list,_newsk)						skb_queue_tail(_list,_newsk)
#define __atbm_skb_dequeue(_list)								__skb_dequeue(_list)
#define atbm_skb_dequeue(_list)									skb_dequeue(_list)
#define __atbm_skb_queue_purge(_list)							__skb_queue_purge(_list)
#define atbm_skb_queue_purge(_list)								skb_queue_purge(_list)
#define atbm_skb_tailroom(_skb)									skb_tailroom(_skb)
#define atbm_skb_queue_empty(_list)								skb_queue_empty(_list)
#define atbm_skb_queue_splice_tail_init(_list,_head)			skb_queue_splice_tail_init(_list,_head)
#define atbm_skb_queue_head_init(_list)							skb_queue_head_init(_list)
#define __atbm_skb_queue_tail(_list,_newsk)						__skb_queue_tail(_list,_newsk)
#define atbm_skb_queue_len(_list_)								skb_queue_len(_list_)
#define __atbm_skb_queue_head_init(_list)						__skb_queue_head_init(_list)
#define __atbm_skb_queue_head(_list,_newsk)						__skb_queue_head(_list,_newsk)
#define atbm_skb_copy(_skb,_gfp_mask)							skb_copy(_skb,_gfp_mask)
#define atbm_skb_pull(_skb,_len)								skb_pull(_skb,_len)
#define atbm_skb_push(_skb,_len)								skb_push(_skb,_len)
#define atbm_netif_rx_ni(_skb)									netif_rx_ni(_skb)
#define atbm_skb_set_queue_mapping(_skb,_queue_mapping)			skb_set_queue_mapping(_skb,_queue_mapping)
#define atbm_skb_set_tail_pointer(_skb,_offset)					skb_set_tail_pointer(_skb,_offset)
#define atbm_skb_reset_tail_pointer(_skb)						skb_reset_tail_pointer(_skb)
#define __atbm_skb_unlink(_skb,_list)							__skb_unlink(_skb,_list)
#define atbm_skb_set_mac_header(_skb,_offset)					skb_set_mac_header(_skb,_offset)
#define atbm_skb_set_network_header(_skb,_offset)				skb_set_network_header(_skb,_offset)
#define atbm_skb_set_transport_header(_skb,_offset)				skb_set_transport_header(_skb,_offset)
#define atbm_skb_queue_splice(_list,_head)						skb_queue_splice(_list,_head)
#define atbm_skb_queue_splice_init(_list,_head)					skb_queue_splice_init(_list,_head)
#define __atbm_pskb_trim(_skb,_len)								__pskb_trim(_skb,_len)
#define atbm_pskb_may_pull(_skb,_len)							pskb_may_pull(_skb,_len)																	
#define atbm_skb_headroom(_skb)									skb_headroom(_skb)
#define atbm_pskb_expand_head(_skb,_nhead,_ntail,_gfp_mask)		pskb_expand_head(_skb,_nhead,_ntail,_gfp_mask)
#define atbm_skb_copy_expand(_skb,_newheadroom,_newtailroom,_gfp_mask)	skb_copy_expand(_skb,_newheadroom,_newtailroom,_gfp_mask)
#define atbm_skb_cloned(_skb)									skb_cloned(_skb)
#define atbm_skb_clone(_skb,_gfp_mask)							skb_clone(_skb,_gfp_mask)
#define atbm_netif_receive_skb(_skb)							netif_receive_skb(_skb)
#define atbm_netif_rx(_skb)										netif_rx(_skb)
#define atbm_dev_queue_xmit(_skb)								dev_queue_xmit(_skb)
#define atbm_skb_linearize(_skb)								skb_linearize(_skb)
#define atbm_skb_peek(_list_)									skb_peek(_list_)
#define atbm_skb_shared(_skb)									skb_shared(_skb)
#define atbm_skb_padto(_skb,_len)  								skb_padto(_skb,_len)
#define atbm_skb_get(_skb)										skb_get(_skb)
#define atbm_skb_orphan(_skb)									skb_orphan(_skb)

#if (LINUX_VERSION_CODE < KERNEL_VERSION(4, 7, 0))
#define atbm_amsdu_to_8023s(_skb, _list,_addr,_iftype,_extra_headroom)		\
		ieee80211_amsdu_to_8023s(_skb, _list,_addr,_iftype,_extra_headroom,true)
#else
#define atbm_amsdu_to_8023s(_skb, _list,_addr,_iftype,_extra_headroom)		\
		ieee80211_amsdu_to_8023s(_skb, _list,_addr,_iftype,_extra_headroom,NULL,NULL)
#endif
#define atbm_skb_tx_debug(_skb)
#define ieee80211_atbm_skb_exit()
#define ieee80211_atbm_skb_int()
#define IEEE80211_ATBM_SKB_HEAD_SIZE 0
#define atbm_skb_rx_debug(_skb,_f)
#define atbm_skb_rx_debug2(_skb,_fc)

#endif

#define atbm_skb_queue_walk_safe(_queue, _skb, _tmp)			skb_queue_walk_safe(_queue, _skb, _tmp)

#endif  //_ATBM_P2P_H_

