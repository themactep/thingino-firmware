/*
 * Copyright 2002-2005, Instant802 Networks, Inc.
 * Copyright 2005-2006, Devicescape Software, Inc.
 * Copyright 2006-2007	Jiri Benc <jbenc@suse.cz>
 * Copyright 2007-2010	Johannes Berg <johannes@sipsolutions.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifdef LINUX_OS
#include <linux/jiffies.h>
#include <linux/slab.h>
#include <linux/kernel.h>
#include <linux/skbuff.h>
#include <linux/if_arp.h>
#include <linux/netdevice.h>
#include <linux/etherdevice.h>
#include <linux/rcupdate.h>
#include <linux/export.h>
#include <net/atbm_mac80211.h>
#include <net/ieee80211_radiotap.h>
#endif

#include "apollo.h"
#include "ieee80211_i.h"
#include "bh.h"

static bool ieee80211_frame_eapol(u8 *data, int len);
static void ieee80211_parse_qos(struct ieee80211_rx_data *rx)
{
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)rx->skb->data;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(rx->skb);
	int tid, seqno_idx, security_idx;

	/* does the frame have a qos control field? */
	if (ieee80211_is_data_qos(hdr->frame_control)) {
		u8 *qc = ieee80211_get_qos_ctl(hdr);
		/* frame has qos control */
		tid = *qc & IEEE80211_QOS_CTL_TID_MASK;
		
		#if (LINUX_VERSION_CODE < KERNEL_VERSION(3, 1, 0))
		if (*qc & IEEE80211_QOS_CONTROL_A_MSDU_PRESENT)
		#else
		if (*qc & IEEE80211_QOS_CTL_A_MSDU_PRESENT)
		#endif
			status->rx_flags |= IEEE80211_RX_AMSDU;

		seqno_idx = tid;
		security_idx = tid;
	} else {
		/*
		 * IEEE 802.11-2007, 7.1.3.4.1 ("Sequence Number field"):
		 *
		 *	Sequence numbers for management frames, QoS data
		 *	frames with a broadcast/multicast address in the
		 *	Address 1 field, and all non-QoS data frames sent
		 *	by QoS STAs are assigned using an additional single
		 *	modulo-4096 counter, [...]
		 *
		 * We also use that counter for non-QoS STAs.
		 */
		seqno_idx = NUM_RX_DATA_QUEUES;
		security_idx = 0;
		if (ieee80211_is_mgmt(hdr->frame_control))
			security_idx = NUM_RX_DATA_QUEUES;
		tid = 0;
	}

	rx->seqno_idx = seqno_idx;
	rx->security_idx = security_idx;
	/* Set skb->priority to 1d tag if highest order bit of TID is not set.
	 * For now, set skb->priority to 0 for other cases. */
	rx->skb->priority = (tid > 7) ? 0 : tid;
}

/**
 * DOC: Packet alignment
 *
 * Drivers always need to pass packets that are aligned to two-byte boundaries
 * to the stack.
 *
 * Additionally, should, if possible, align the payload data in a way that
 * guarantees that the contained IP header is aligned to a four-byte
 * boundary. In the case of regular frames, this simply means aligning the
 * payload to a four-byte boundary (because either the IP header is directly
 * contained, or IV/RFC1042 headers that have a length divisible by four are
 * in front of it).  If the payload data is not properly aligned and the
 * architecture doesn't support efficient unaligned operations, mac80211
 * will align the data.
 *
 * With A-MSDU frames, however, the payload data address must yield two modulo
 * four because there are 14-byte 802.3 headers within the A-MSDU frames that
 * push the IP header further back to a multiple of four again. Thankfully, the
 * specs were sane enough this time around to require padding each A-MSDU
 * subframe to a length that is a multiple of four.
 *
 * Padding like Atheros hardware adds which is between the 802.11 header and
 * the payload is not supported, the driver is required to move the 802.11
 * header to be directly in front of the payload in that case.
 */
static void ieee80211_verify_alignment(struct ieee80211_rx_data *rx)
{
#ifdef CONFIG_MAC80211_ATBM_VERBOSE_DEBUG
	WARN_ONCE((unsigned long)rx->skb->data & 1,
		  "unaligned packet at 0x%p\n", rx->skb->data);
#endif
}

#define SEQ_MODULO 0x1000
#define SEQ_MASK   0xfff

static inline int seq_less(u16 sq1, u16 sq2)
{
	return ((sq1 - sq2) & SEQ_MASK) > (SEQ_MODULO >> 1);
}

static inline u16 seq_inc(u16 sq)
{
	return (sq + 1) & SEQ_MASK;
}

static inline u16 seq_sub(u16 sq1, u16 sq2)
{
	return (sq1 - sq2) & SEQ_MASK;
}


static void ieee80211_release_reorder_frame(struct atbm_common *hw_priv,
					    struct tid_ampdu_rx *tid_agg_rx,
					    int index,struct sk_buff_head *frames)
{
	struct sk_buff *skb = tid_agg_rx->reorder_buf[index];
	struct ieee80211_rx_status *status;

	lockdep_assert_held(&tid_agg_rx->reorder_lock);

	if (!skb)
		goto no_frame;

	/* release the frame from the reorder ring buffer */
	tid_agg_rx->stored_mpdu_num--;
	tid_agg_rx->reorder_buf[index] = NULL;
	status = IEEE80211_SKB_RXCB(skb);
	status->rx_flags |= IEEE80211_RX_DEFERRED_RELEASE;
	__atbm_skb_queue_tail(frames, skb);

no_frame:
	tid_agg_rx->head_seq_num = seq_inc(tid_agg_rx->head_seq_num);
}

static void ieee80211_release_reorder_frames(struct atbm_common *hw_priv,
					     struct tid_ampdu_rx *tid_agg_rx,
					     u16 head_seq_num,struct sk_buff_head *frames)
{
	int index;

	lockdep_assert_held(&tid_agg_rx->reorder_lock);

	while (seq_less(tid_agg_rx->head_seq_num, head_seq_num)) {
		index = seq_sub(tid_agg_rx->head_seq_num, tid_agg_rx->ssn) %
							tid_agg_rx->buf_size;
		ieee80211_release_reorder_frame(hw_priv, tid_agg_rx, index,frames);
	}
}

/*
 * Timeout (in jiffies) for skb's that are waiting in the RX reorder buffer. If
 * the skb was added to the buffer longer than this time ago, the earlier
 * frames that have not yet been received are assumed to be lost and the skb
 * can be released for processing. This may also release other skb's from the
 * reorder buffer if there are no additional gaps between the frames.
 *
 * Callers must hold tid_agg_rx->reorder_lock.
 */
static int HT_RX_REORDER_BUF_TIMEOUT = (HZ / 3);
static int Sta_shortTcp_RxCnt = 0;
static void ieee80211_sta_reorder_release(struct atbm_common *hw_priv,
					  struct tid_ampdu_rx *tid_agg_rx,struct sk_buff_head *frames)
{
	int index, j;

	lockdep_assert_held(&tid_agg_rx->reorder_lock);

	/* release the buffer until next missing frame */
	index = seq_sub(tid_agg_rx->head_seq_num, tid_agg_rx->ssn) %
						tid_agg_rx->buf_size;
	if (!tid_agg_rx->reorder_buf[index] &&
	    tid_agg_rx->stored_mpdu_num) {
		/*
		 * No buffers ready to be released, but check whether any
		 * frames in the reorder buffer have timed out.
		 */
		int skipped = 1;
		for (j = (index + 1) % tid_agg_rx->buf_size; j != index;
		     j = (j + 1) % tid_agg_rx->buf_size) {
			if (!tid_agg_rx->reorder_buf[j]) {
				skipped++;
				continue;
			}
			if (skipped &&
			    !time_after(jiffies, tid_agg_rx->reorder_time[j] +
					HT_RX_REORDER_BUF_TIMEOUT))
				goto set_release_timer;
			if(skipped){
				//printk("release an RX reorder frame due to timeout sn %x\n",tid_agg_rx->head_seq_num);
			}
			ieee80211_release_reorder_frame(hw_priv, tid_agg_rx, j,frames);

			/*
			 * Increment the head seq# also for the skipped slots.
			 */
			tid_agg_rx->head_seq_num =
				(tid_agg_rx->head_seq_num + skipped) & SEQ_MASK;
			skipped = 0;
		}
	} else while (tid_agg_rx->reorder_buf[index]) {
		ieee80211_release_reorder_frame(hw_priv, tid_agg_rx, index,frames);
		index =	seq_sub(tid_agg_rx->head_seq_num, tid_agg_rx->ssn) %
							tid_agg_rx->buf_size;
	}

	if (tid_agg_rx->stored_mpdu_num) {
		j = index = seq_sub(tid_agg_rx->head_seq_num,
				    tid_agg_rx->ssn) % tid_agg_rx->buf_size;

		for (; j != (index - 1) % tid_agg_rx->buf_size;
		     j = (j + 1) % tid_agg_rx->buf_size) {
			if (tid_agg_rx->reorder_buf[j])
				break;
		}

 set_release_timer:

		atbm_mod_timer(&tid_agg_rx->reorder_timer,
			  tid_agg_rx->reorder_time[j] + 1 +
			  HT_RX_REORDER_BUF_TIMEOUT);
	} else {
		atbm_del_timer(&tid_agg_rx->reorder_timer);
	}
}

/*
 * As this function belongs to the RX path it must be under
 * rcu_read_lock protection. It returns false if the frame
 * can be processed immediately, true if it was consumed.
 */
static bool ieee80211_sta_manage_reorder_buf(struct atbm_common *hw_priv,
					     struct tid_ampdu_rx *tid_agg_rx,
					     struct sk_buff *skb,struct sk_buff_head *frames)
{
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *) skb->data;
	u16 sc = le16_to_cpu(hdr->seq_ctrl);
	u16 mpdu_seq_num = (sc & IEEE80211_SCTL_SEQ) >> 4;
	u16 head_seq_num, buf_size;
	int index;
	bool ret = true;
	bool isEapol = (ieee80211_is_data(hdr->frame_control) &&
				ieee80211_frame_eapol(skb->data, skb->len));

	if(skb->len < 150){
		Sta_shortTcp_RxCnt++;
		if(Sta_shortTcp_RxCnt > 50){
			Sta_shortTcp_RxCnt = 50;
			HT_RX_REORDER_BUF_TIMEOUT = HZ/4;
		}
	}
	else {
		if(Sta_shortTcp_RxCnt >= 20)
			Sta_shortTcp_RxCnt -= 20;
		if (Sta_shortTcp_RxCnt < 20)
		{
			Sta_shortTcp_RxCnt = 0;
			HT_RX_REORDER_BUF_TIMEOUT = HZ/2;
		}
	}
	spin_lock(&tid_agg_rx->reorder_lock);

	buf_size = tid_agg_rx->buf_size;
	head_seq_num = tid_agg_rx->head_seq_num;

	/* frame with out of date sequence number */
	if (seq_less(mpdu_seq_num, head_seq_num)) {
		atbm_dev_kfree_skb(skb);
		goto out;
	}

	/*
	 * If frame the sequence number exceeds our buffering window
	 * size release some previous frames to make room for this one.
	 */
	if (!seq_less(mpdu_seq_num, head_seq_num + buf_size)) {
		head_seq_num = seq_inc(seq_sub(mpdu_seq_num, buf_size));
		/* release stored frames up to new head to stack */
		ieee80211_release_reorder_frames(hw_priv, tid_agg_rx, head_seq_num,frames);
	}

	/* Now the new frame is always in the range of the reordering buffer */

	index = seq_sub(mpdu_seq_num, tid_agg_rx->ssn) % tid_agg_rx->buf_size;

	/* check if we already stored this frame */
	if (tid_agg_rx->reorder_buf[index]) {
		atbm_dev_kfree_skb(skb);
		goto out;
	}

	/*
	 * If the current MPDU is in the right order and nothing else
	 * is stored we can process it directly, no need to buffer it.
	 * If it is first but there's something stored, we may be able
	 * to release frames after this one.
	 */
	if (mpdu_seq_num == tid_agg_rx->head_seq_num &&
	    tid_agg_rx->stored_mpdu_num == 0) {
		tid_agg_rx->head_seq_num = seq_inc(tid_agg_rx->head_seq_num);
		ret = false;
		goto out;
	}

	if (isEapol && mpdu_seq_num == (tid_agg_rx->head_seq_num + 1) &&
		tid_agg_rx->stored_mpdu_num == 0) {
		tid_agg_rx->head_seq_num = seq_inc(tid_agg_rx->head_seq_num);
		ret = false;
		goto out;
	}

	/* put the frame in the reordering buffer */
	tid_agg_rx->reorder_buf[index] = skb;
	tid_agg_rx->reorder_time[index] = jiffies;
	tid_agg_rx->stored_mpdu_num++;
	ieee80211_sta_reorder_release(hw_priv, tid_agg_rx,frames);

 out:
	spin_unlock(&tid_agg_rx->reorder_lock);
	return ret;
}

/*
 * Reorder MPDUs from A-MPDUs, keeping them on a buffer. Returns
 * true if the MPDU was buffered, false if it should be processed.
 */
static void ieee80211_rx_reorder_ampdu(struct ieee80211_rx_data *rx,struct sk_buff_head *frames)
{
	struct sk_buff *skb = rx->skb;
	struct atbm_common *hw_priv = rx->hw_priv;
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *) skb->data;
	struct sta_info *sta = rx->sta;
	struct tid_ampdu_rx *tid_agg_rx;
	u16 sc;
	int tid;

	if (!ieee80211_is_data_qos(hdr->frame_control))
		goto dont_reorder;

	/*
	 * filter the QoS data rx stream according to
	 * STA/TID and check if this STA/TID is on aggregation
	 */

	if (!sta)
		goto dont_reorder;

	tid = *(int *)ieee80211_get_qos_ctl(hdr) & IEEE80211_QOS_CTL_TID_MASK;

	tid_agg_rx = rcu_dereference(sta->ampdu_mlme.tid_rx[tid]);
	if (!tid_agg_rx)
		goto dont_reorder;

	/* qos null data frames are excluded */
	if (unlikely(hdr->frame_control & cpu_to_le16(IEEE80211_STYPE_NULLFUNC)))
		goto dont_reorder;

	/* new, potentially un-ordered, ampdu frame - process it */

	/* reset session timer */
	if (tid_agg_rx->timeout)
		atbm_mod_timer(&tid_agg_rx->session_timer,
			  TU_TO_EXP_TIME(tid_agg_rx->timeout));

	/* if this mpdu is fragmented - terminate rx aggregation session */
	sc = le16_to_cpu(hdr->seq_ctrl);
	if (sc & IEEE80211_SCTL_FRAG) {
		atbm_printk_err("%s:dont process fragment\n",__func__);
		goto dont_reorder;
	}

	/*
	 * No locking needed -- we will only ever process one
	 * RX packet at a time, and thus own tid_agg_rx. All
	 * other code manipulating it needs to (and does) make
	 * sure that we cannot get to it any more before doing
	 * anything with it.
	 */
	if (ieee80211_sta_manage_reorder_buf(hw_priv, tid_agg_rx, skb,frames))
		return;

 dont_reorder:
	__atbm_skb_queue_tail(frames, skb);
}

static bool ieee80211_frame_eapol(u8 *data, int len)
{
	__le16 fc;
	bool status = false;

#define ETH_TYPE_OFFSET 30

	fc = ((struct ieee80211_hdr *)data)->frame_control;
	if ((ieee80211_is_data(fc)) && (len > 34)) {
		u8 eapol_index = ETH_TYPE_OFFSET;
		u16 ethertype;

		if (ieee80211_is_data_qos(fc))
			eapol_index = ETH_TYPE_OFFSET + 2;

		ethertype = ((data[eapol_index] << 8) |
				(data[eapol_index + 1]));
		if (ethertype == ETH_P_PAE)
			status = true;
	}
	return status;
}

static ieee80211_rx_result
ieee80211_rx_h_check(struct ieee80211_rx_data *rx)
{
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)rx->skb->data;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(rx->skb);

	/* Drop duplicate 802.11 retransmissions (IEEE 802.11 Chap. 9.2.9) */
	if (rx->sta && !is_multicast_ether_addr(hdr->addr1)) {
		if (unlikely(ieee80211_has_retry(hdr->frame_control) &&
			     rx->sta->last_seq_ctrl[rx->seqno_idx] ==
			     hdr->seq_ctrl)) {
			if (status->rx_flags & IEEE80211_RX_RA_MATCH) {
				;
			}
			return RX_DROP_UNUSABLE;
		} else
			rx->sta->last_seq_ctrl[rx->seqno_idx] = hdr->seq_ctrl;
	}

	if (unlikely(rx->skb->len < 16)) {
		return RX_DROP_MONITOR;
	}	
	if (unlikely((ieee80211_is_data(hdr->frame_control) ||
		      ieee80211_is_pspoll(hdr->frame_control))
		    && (!rx->sta || !test_sta_flag(rx->sta, WLAN_STA_ASSOC)))) {
		return RX_DROP_MONITOR;
	}

	return RX_CONTINUE;
}
static ieee80211_rx_result
ieee80211_crypto_wep_decrypt(struct ieee80211_rx_data *rx)
{
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)skb->data;

	if (!ieee80211_is_data(hdr->frame_control) &&
	    !ieee80211_is_auth(hdr->frame_control))
		return RX_CONTINUE;
	
	if(!(status->flag & RX_FLAG_DECRYPTED)){
		atbm_printk_err("wep decr err\n");
		return RX_DROP_UNUSABLE;
	}
	if (!(status->flag & RX_FLAG_IV_STRIPPED)) {
		unsigned int hdrlen;

		hdrlen = ieee80211_hdrlen(hdr->frame_control);
		memmove(skb->data + WEP_IV_LEN, skb->data, hdrlen);
		atbm_skb_pull(skb, WEP_IV_LEN);
		/* remove ICV */
		atbm_skb_trim(rx->skb, rx->skb->len - WEP_ICV_LEN);
	}

	return RX_CONTINUE;
}
static ieee80211_rx_result
ieee80211_crypto_tkip_decrypt(struct ieee80211_rx_data *rx)
{
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *) rx->skb->data;
	int hdrlen = 0;
	struct sk_buff *skb = rx->skb;

	hdrlen = ieee80211_hdrlen(hdr->frame_control);

	if (!ieee80211_is_data(hdr->frame_control))
		return RX_CONTINUE;

	if (!rx->sta || skb->len - hdrlen < 12)
		return RX_DROP_UNUSABLE;

	/* Trim ICV */
	atbm_skb_trim(skb, skb->len - TKIP_ICV_LEN);

	/* Remove IV */
	memmove(skb->data + TKIP_IV_LEN, skb->data, hdrlen);
	atbm_skb_pull(skb, TKIP_IV_LEN);

	return RX_CONTINUE;
}

static ieee80211_rx_result
ieee80211_crypto_ccmp_decrypt(struct ieee80211_rx_data *rx)
{
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)rx->skb->data;
	int hdrlen;
	struct sk_buff *skb = rx->skb;
	int data_len;

	hdrlen = ieee80211_hdrlen(hdr->frame_control);

	if (!ieee80211_is_data(hdr->frame_control) &&
	#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,17,0))
	    !ieee80211_is_robust_mgmt_frame(hdr)
	#else
		 !ieee80211_is_robust_mgmt_frame(skb)
	#endif
	    )
		return RX_CONTINUE;

	data_len = skb->len - hdrlen - CCMP_HDR_LEN - CCMP_MIC_LEN;
	if (!rx->sta || data_len < 0)
		return RX_DROP_UNUSABLE;
	
	/* Remove CCMP header and MIC */
	atbm_skb_trim(skb, skb->len - CCMP_MIC_LEN);
	memmove(skb->data + CCMP_HDR_LEN, skb->data, hdrlen);
	atbm_skb_pull(skb, CCMP_HDR_LEN);

	return RX_CONTINUE;
}
static ieee80211_rx_result
ieee80211_crypto_aes_cmac_decrypt(struct ieee80211_rx_data *rx)
{
	struct sk_buff *skb = rx->skb;
	struct ieee80211_mmie *mmie;
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *) skb->data;

	if (!ieee80211_is_mgmt(hdr->frame_control))
		return RX_CONTINUE;

	if (skb->len < 24 + sizeof(*mmie))
		return RX_DROP_UNUSABLE;

	mmie = (struct ieee80211_mmie *)
		(skb->data + skb->len - sizeof(*mmie));
	if (mmie->element_id != ATBM_WLAN_EID_MMIE ||
	    mmie->length != sizeof(*mmie) - 2)
		return RX_DROP_UNUSABLE; /* Invalid MMIE */
	/* Remove MMIE */
	atbm_skb_trim(skb, skb->len - sizeof(*mmie));

	return RX_CONTINUE;
}

static void ccmp_tkip_hdr2pn(u8 *pn, u8 *hdr, bool is_ccmp)
{
	pn[0] = hdr[7];
	pn[1] = hdr[6];
	pn[2] = hdr[5];
	pn[3] = hdr[4];
	if (is_ccmp){
		pn[4] = hdr[1];
		pn[5] = hdr[0];
	}
	else {
		pn[4] = hdr[0];
		pn[5] = hdr[2];
	}
}

#define BUFF_STORED_LEN		(64)
#define SEQ_NUM_MASKER		(0xfff)

struct replay_cnt_info{
	unsigned short frame_replaycnt_table[BUFF_STORED_LEN];//save replaycnt low
	unsigned char frame_replaycnt_fillcnt[BUFF_STORED_LEN];//check insert
	unsigned short frame_replaycnt_base_low;//pn low 2bytes
	unsigned int   frame_replaycnt_base_high;//pn high 4bytes
	unsigned short frame_replaycnt_offset_ssn;//保存到table中最小frame_replaycnt_table
	unsigned short sn;//窗口最小sn
	unsigned short sn_max;//窗口最大sn
};
struct replay_cnt_info replay_inf[8/*tid max num*/] = {0};

static void atbm_flush_replay(u16 sn, u8 tid)
{
	/*如果replaycnt的offset 太大容易越界,所以将replaycnt_base 增大*/
	int k;
	int idex = sn&(BUFF_STORED_LEN-1);
	u16 lowest_replay=0;

	/*更新基准replaycnt_low*/
	replay_inf[tid].frame_replaycnt_base_low += 0x8000;
	if(replay_inf[tid].frame_replaycnt_base_low < 0x8000){
		replay_inf[tid].frame_replaycnt_base_high++;
	}

	/*获取最低SN index*/
	idex++;

	if (replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] < 0x8000){
		replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] = 0x8000;
	}
	lowest_replay = replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] - 0x8000;

	/*更新最小replaycnt_low*/
	if (replay_inf[tid].frame_replaycnt_offset_ssn < 0x8000){
		replay_inf[tid].frame_replaycnt_offset_ssn = 0;
	}
	else {
		replay_inf[tid].frame_replaycnt_offset_ssn -= 0x8000;
	}
	/*低向高顺延更新基准replaycnt_low*/
	for (k=0;k<=63;k++){
		if (replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] > 0x8000){
			replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] -= 0x8000;
			if (replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] > lowest_replay){
				lowest_replay = replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)];
			}
		}
		else {
			
			replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] = lowest_replay;
		}
		idex++;
	}
}

static int ccmp_tkip_replaycnt_loop_backup(struct atbm_vif *vif,struct ieee80211_mgmt *mgmt, bool is_ccmp)
{
	u8 pn[CCMP_PN_LEN];
	int hdrlen = ieee80211_hdrlen(mgmt->frame_control);
	u8 *qc = ieee80211_get_qos_ctl((struct ieee80211_hdr *)mgmt);
	u8 tid = *qc & 0x7;//IEEE80211_QOS_CTL_TID_MASK;
	u8 *pOldPN;
	u8 *b_pn_init;
	u8 pn_type = 0;
	u16 sn = mgmt->seq_ctrl>>4;
	unsigned short tmp_replaycnt_base_low;
	unsigned int tmp_replaycnt_base_high;
	int i;
	int idex;
	int len;

	if (vif->type != NL80211_IFTYPE_STATION){
		return 0;
	}

	ccmp_tkip_hdr2pn(pn,(u8 *)mgmt + hdrlen, is_ccmp);

	tmp_replaycnt_base_low = pn[5]|(pn[4]<<8);
	tmp_replaycnt_base_high = pn[3]|(pn[2]<<8)|(pn[1]<<16)|(pn[0]<<24);

	if (is_multicast_ether_addr(mgmt->da) == 0){
		if (ieee80211_is_data_qos(mgmt->frame_control)){
			pOldPN = vif->ptk_pn[tid];
			b_pn_init = &(vif->ptk_pn_init[tid]);
			pn_type = 0;
		}
		else {
			pOldPN = vif->ptk_noqos_pn;
			b_pn_init = &(vif->ptk_noqos_pn_init);
			pn_type = 1;
		}
	}
	else {
		pOldPN = vif->gtk_pn;
		b_pn_init = &(vif->gtk_pn_init);
		pn_type = 2;
	}


	if (*b_pn_init == 0){
		/*新包PN小于存储的最大PN*/
		if (memcmp(pn, pOldPN, CCMP_PN_LEN) <= 0){
			/*QosData乱序PN检测*/
			if (pn_type == 0){
				goto reorder_check;
			}
			else {
				/*非QosData乱序直接丢弃*/
				goto __drop;
			}
		}
		else if (pn_type == 0){
			/*如果收到的PN比旧的存储大，则应永为新包*/
			if (tmp_replaycnt_base_high > replay_inf[tid].frame_replaycnt_base_high){
				replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] = (unsigned int)tmp_replaycnt_base_low + 0x10000 - (unsigned int)replay_inf[tid].frame_replaycnt_base_low;
			}
			else {
				replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] = tmp_replaycnt_base_low - replay_inf[tid].frame_replaycnt_base_low;
			}
			/*如果replaycnt的offset太大容易越界,所以将replaycnt_base增大*/
			if (replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] > 0x9000){
				atbm_flush_replay(sn, tid);
			}
			/*如果收到的是first同时replay_inf.sn_max==replay_inf.sn*/
			if (replay_inf[tid].sn == sn){
				replay_inf[tid].sn = (sn+1)&SEQ_NUM_MASKER;
				replay_inf[tid].sn_max = (sn+1)&SEQ_NUM_MASKER;
			}
			else {
				replay_inf[tid].frame_replaycnt_fillcnt[sn&(BUFF_STORED_LEN-1)] = 1;
				replay_inf[tid].sn_max = sn;
				/*如果收到的超过窗*2*/
				if (((sn-replay_inf[tid].sn)&SEQ_NUM_MASKER)>=(BUFF_STORED_LEN*2-1)){
					/*以新SN为最大向前减一个窗口区为最小SN*/
					replay_inf[tid].sn = (sn-63)&SEQ_NUM_MASKER;
					idex = replay_inf[tid].sn&(BUFF_STORED_LEN-1);
					/*窗口区前置清空*/
					for (i=0;i<63;i++){
						replay_inf[tid].frame_replaycnt_fillcnt[idex&(BUFF_STORED_LEN-1)] = 0;
						idex++;
					}
				}	/*如果收到的超过窗口*1*/
				else if (((sn-replay_inf[tid].sn)&SEQ_NUM_MASKER)>=(BUFF_STORED_LEN-1)){
					/*以新SN为最大向前减一个窗口区为最小SN*/
					replay_inf[tid].sn = (sn-63)&SEQ_NUM_MASKER;
					idex = replay_inf[tid].sn&(BUFF_STORED_LEN-1);
					len = (sn-replay_inf[tid].sn)-(BUFF_STORED_LEN-1);
					/*窗口区前置清空*/
					for (i=0;i<len;i++){
						idex--;
						replay_inf[tid].frame_replaycnt_fillcnt[idex&(BUFF_STORED_LEN-1)]=0;
					}
					for(i=0;i<=63;i++){
						/*填充位重置，更新最小offset_ssn*/
						if(replay_inf[tid].frame_replaycnt_fillcnt[idex&(BUFF_STORED_LEN-1)]){
							replay_inf[tid].frame_replaycnt_fillcnt[idex&(BUFF_STORED_LEN-1)]=0;
							if(replay_inf[tid].frame_replaycnt_offset_ssn < replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)]){
								//printf("[%d]change frame_replaycnt_offset_ssn %d >> %d\n",idex,replay_inf[tid].frame_replaycnt_offset_ssn , replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)]);
								replay_inf[tid].frame_replaycnt_offset_ssn = replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] ;
							}
							idex++;
						}
						else {
							break;
						}
					}
				}
			}
		}
	}
	else {
		//if first PN just update
		*b_pn_init = 0;
		if (pn_type == 0){
			replay_inf[tid].frame_replaycnt_base_low = tmp_replaycnt_base_low;
			replay_inf[tid].frame_replaycnt_base_high = tmp_replaycnt_base_high;
			replay_inf[tid].sn = (sn+1)&SEQ_NUM_MASKER;
			replay_inf[tid].sn_max = (sn+1)&SEQ_NUM_MASKER;
			replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] = 0;
			replay_inf[tid].frame_replaycnt_offset_ssn = 0;
			memset(replay_inf[tid].frame_replaycnt_fillcnt,0,sizeof(replay_inf[tid].frame_replaycnt_fillcnt[0])*BUFF_STORED_LEN);
			replay_inf[tid].frame_replaycnt_fillcnt[sn&(BUFF_STORED_LEN-1)] = 1;
		}
	}
	//新PN直接更新
	memcpy(pOldPN, pn, CCMP_PN_LEN);
	return 0;

reorder_check:
	if (pn_type == 0){
		/*如果收到的是最小SN*/
		if (replay_inf[tid].sn == sn){
			replay_inf[tid].frame_replaycnt_fillcnt[sn&(BUFF_STORED_LEN-1)] = 1;
		}
		/*新SN超过窗口区范围*/
		if (((replay_inf[tid].sn_max-sn)&SEQ_NUM_MASKER)>=(BUFF_STORED_LEN)){
				atbm_printk_err("__drop 0,replay_inf.sn_max %d sn %d [%d>64]\n",replay_inf[tid].sn_max,sn,((replay_inf[tid].sn_max-sn)&SEQ_NUM_MASKER));
				goto __drop;
		}
		/*新包PN比基准PN高位大，直接存储（不应该发生）*/
		if (tmp_replaycnt_base_high > replay_inf[tid].frame_replaycnt_base_high){
			replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] = (unsigned int)tmp_replaycnt_base_low + 0x10000 - (unsigned int)replay_inf[tid].frame_replaycnt_base_low;
			/*如果replaycnt的offset太大容易越界,所以将replaycnt_base增大*/
			if (replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] > 0x9000){
				atbm_flush_replay(sn, tid);
			}
		}
		/*新包replaycnt低位比存储窗口区最低位还小*/
		else if(tmp_replaycnt_base_low <= replay_inf[tid].frame_replaycnt_base_low){
			atbm_printk_err("__drop 1,replay_base_low [%d<=%d]\n",tmp_replaycnt_base_low,replay_inf[tid].frame_replaycnt_base_low);
			goto __drop;
		}
		/*新包replaycnt低位offset比存储窗口区最小offset还小*/
		else if(replay_inf[tid].frame_replaycnt_offset_ssn >= tmp_replaycnt_base_low - replay_inf[tid].frame_replaycnt_base_low){
			atbm_printk_err("__drop 2, frame_replaycnt_offset_ssn %d >= %d,low %d\n",replay_inf[tid].frame_replaycnt_offset_ssn,tmp_replaycnt_base_low - replay_inf[tid].frame_replaycnt_base_low,replay_inf[tid].frame_replaycnt_base_low);
			goto __drop;
		}
		else {
			/*满足插入条件*/
			unsigned short frame_replaycnt_table_tmp = tmp_replaycnt_base_low - replay_inf[tid].frame_replaycnt_base_low;
			if (replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] >= frame_replaycnt_table_tmp){
				atbm_printk_err("__drop 3,frame_replaycnt_table [%d<=%d]\n",frame_replaycnt_table_tmp,replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)]);
				goto __drop;
			}
			replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)] = frame_replaycnt_table_tmp;
		}
		/*遍历SN低窗口区，检测replaycnt_table_low*/
		{
			idex = replay_inf[tid].sn&(BUFF_STORED_LEN-1);
			for (i=0;i<=63;i++){
				if((idex&(BUFF_STORED_LEN-1)) != (sn&(BUFF_STORED_LEN-1))){
					if (replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)] >= replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)]){
						atbm_printk_err("__drop 4, repalycnt loop window error [%d<=%d]\n",replay_inf[tid].frame_replaycnt_table[sn&(BUFF_STORED_LEN-1)],replay_inf[tid].frame_replaycnt_table[idex&(BUFF_STORED_LEN-1)]);
						goto __drop;
					}
					idex++;
				}
				else {
					break;
				}
			}
		}
		/*如果收到的是最小SN，遍历释放已存储低位SN存储区*/
		if (replay_inf[tid].sn == sn){
			idex = replay_inf[tid].sn&(BUFF_STORED_LEN-1);
			for (i=0;i<=63;i++){
				if (replay_inf[tid].frame_replaycnt_fillcnt[idex&(BUFF_STORED_LEN-1)]){
					replay_inf[tid].frame_replaycnt_fillcnt[idex&(BUFF_STORED_LEN-1)] = 0;
					replay_inf[tid].sn = (replay_inf[tid].sn+1)&SEQ_NUM_MASKER;
					idex++;
				}
				else {
					break;
				}
			}
		}
	}

	return 0;

__drop:
	atbm_printk_err("[RX Drop pn_type %d]sn=%d ccmp_replaycnt drop %x:%x:%x:%x:%x:%x > %x:%x:%x:%x:%x:%x \n",pn_type,sn
										,pOldPN[0]
										,pOldPN[1]
										,pOldPN[2]
										,pOldPN[3]
										,pOldPN[4]
										,pOldPN[5]
										,pn[0]
										,pn[1]
										,pn[2]
										,pn[3]
										,pn[4]
										,pn[5]);
	atbm_printk_err("id _mul %d\n",is_multicast_ether_addr(mgmt->da));
	return -1;
}

#define USE_LOOP_BACKUP_REPLAYCNT 0
static int ccmp_tkip_replaycnt(struct atbm_vif *vif, struct ieee80211_mgmt *mgmt, bool is_ccmp)
{
	u8 pn[CCMP_PN_LEN];
	static const u8 zero_pn[CCMP_PN_LEN]= {0};
	int hdrlen = ieee80211_hdrlen(mgmt->frame_control);
	u8 *qc = ieee80211_get_qos_ctl((struct ieee80211_hdr *)mgmt);
	u8 tid = *qc & 0x7;//IEEE80211_QOS_CTL_TID_MASK;
	u8 *pOldPN;
	u8 *b_pn_init;

	if (USE_LOOP_BACKUP_REPLAYCNT){
		return ccmp_tkip_replaycnt_loop_backup(vif, mgmt, is_ccmp);
	}

	if (vif->type != NL80211_IFTYPE_STATION){
		return 0;
	}

	ccmp_tkip_hdr2pn(pn,(u8 *)mgmt + hdrlen, is_ccmp);

	if (is_multicast_ether_addr(mgmt->da) == 0){
		if (ieee80211_is_data_qos(mgmt->frame_control)){
			pOldPN = vif->ptk_pn[tid];
			b_pn_init = &(vif->ptk_pn_init[tid]);
		}
		else {
			pOldPN = vif->ptk_noqos_pn;
			b_pn_init = &(vif->ptk_noqos_pn_init);
		}
	}
	else {
		pOldPN = vif->gtk_pn;
		b_pn_init = &(vif->gtk_pn_init);
	}

	if (*b_pn_init == 0){
		if (memcmp(pn, pOldPN, CCMP_PN_LEN) <= 0){
			if (!((memcmp(pn, zero_pn, CCMP_PN_LEN) == 0) && (memcmp(pOldPN, zero_pn, CCMP_PN_LEN) == 0))){
				atbm_printk_err("[RX]ccmp_tkip_replaycnt drop %x:%x:%x:%x:%x:%x > %x:%x:%x:%x:%x:%x\n",
					pOldPN[0],pOldPN[1],pOldPN[2],pOldPN[3],pOldPN[4],pOldPN[5],
					pn[0],pn[1],pn[2],pn[3],pn[4],pn[5]);
			}
			return -1;
		}
		else {
			int i = 0;
			for (i=0; i<CCMP_PN_LEN; i++){
				if (pn[i] > pOldPN[i]){
					//PN = xx,xx,xx,xx,0,0
					if (i >= CCMP_PN_LEN-2){
						break;
					}
					else {
						//PN = 1,0,0,0,0,0
						//pOldPN = 0,0xff,0xff,0xff,0,0
						if ((pn[i] != (pOldPN[i]+1))
							|| (pOldPN[i+1] != 0xff)
							|| (pn[i+1] != 0)){
							atbm_printk_warn("[RX]ccmp_tkip_replaycnt not update\n");
							return 0;
						}
					}
				}
			}
		}
	}
	else {
		*b_pn_init = 0;
	}

	memcpy(pOldPN, pn, CCMP_PN_LEN);
	return 0;
}

static ieee80211_rx_result
ieee80211_rx_h_decrypt(struct ieee80211_rx_data *rx)
{
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	ieee80211_rx_result result = RX_DROP_UNUSABLE;
	struct ieee80211_hdr *hdr = (void *)skb->data;
	/*
	 * Key selection 101
	 *
	 * There are four types of keys:
	 *  - GTK (group keys)
	 *  - IGTK (group keys for management frames)
	 *  - PTK (pairwise keys)
	 *  - STK (station-to-station pairwise keys)
	 *
	 * When selecting a key, we have to distinguish between multicast
	 * (including broadcast) and unicast frames, the latter can only
	 * use PTKs and STKs while the former always use GTKs and IGTKs.
	 * Unless, of course, actual WEP keys ("pre-RSNA") are used, then
	 * unicast frames can also use key indices like GTKs. Hence, if we
	 * don't have a PTK/STK we check the key index for a WEP key.
	 *
	 * Note that in a regular BSS, multicast frames are sent by the
	 * AP only, associated stations unicast the frame to the AP first
	 * which then multicasts it on their behalf.
	 *
	 * There is also a slight problem in IBSS mode: GTKs are negotiated
	 * with each station, that is something we don't currently handle.
	 * The spec seems to expect that one negotiates the same key with
	 * every station but there's no such requirement; VLANs could be
	 * possible.
	 */

	/*
	 * No point in finding a key and decrypting if the frame is neither
	 * addressed to us nor a multicast frame.
	 */
	rx->key = NULL;
	
	if (!(status->rx_flags & IEEE80211_RX_RA_MATCH))
		return RX_CONTINUE;

	if (atbm_skb_linearize(rx->skb))
		return RX_DROP_UNUSABLE;

	if(rx->sta == NULL)
		return RX_CONTINUE;

	if(rx->sta->enc == false)
		return RX_CONTINUE;

	if(!(status->flag & RX_FLAG_DECRYPTED))
		return RX_CONTINUE;

	if(status->flag & RX_FLAG_IV_STRIPPED)
		return RX_CONTINUE;
		
	/* the hdr variable is invalid now! */
	if(is_multicast_ether_addr(hdr->addr1))
		rx->key = &rx->vif->group_key;
	else 
		rx->key = &rx->sta->key;
	
	switch (rx->key->key_type) {
	case IEEE80211_ENC_WEP:
		result = ieee80211_crypto_wep_decrypt(rx);
		break;
	case IEEE80211_ENC_TKIP:
		if (ccmp_tkip_replaycnt(rx->vif, (struct ieee80211_mgmt *)hdr, false))
			return RX_DROP_UNUSABLE;
		result = ieee80211_crypto_tkip_decrypt(rx);
		break;
	case IEEE80211_ENC_AES:
		if (ccmp_tkip_replaycnt(rx->vif, (struct ieee80211_mgmt *)hdr, true))
			return RX_DROP_UNUSABLE;
		result = ieee80211_crypto_ccmp_decrypt(rx);
		break;
	case IEEE80211_ENC_AES_CMAC:
		result = ieee80211_crypto_aes_cmac_decrypt(rx);
		break;
	default:
		/*
		 * We can reach here only with HW-only algorithms
		 * but why didn't it decrypt the frame?!
		 */
		return RX_DROP_UNUSABLE;
	}

	/* either the frame has been decrypted or will be dropped */
	status->flag |= RX_FLAG_DECRYPTED;

	return result;
}

static ieee80211_rx_result
ieee80211_rx_h_sta_process(struct ieee80211_rx_data *rx)
{
	struct sta_info *sta = rx->sta;
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)skb->data;

	if (!sta)
		return RX_CONTINUE;

	if (!(status->rx_flags & IEEE80211_RX_RA_MATCH))
		return RX_CONTINUE;
	/*
	 * Drop (qos-)data::nullfunc frames silently, since they
	 * are used only to control station power saving mode.
	 */
	if (ieee80211_is_nullfunc(hdr->frame_control) ||
	    ieee80211_is_qos_nullfunc(hdr->frame_control)) {
		atbm_dev_kfree_skb(rx->skb);
		return RX_QUEUED;
	}

	return RX_CONTINUE;
} /* ieee80211_rx_h_sta_process */
static ieee80211_rx_result
ieee80211_rx_h_remove_qos_control(struct ieee80211_rx_data *rx)
{
	u8 *data = rx->skb->data;
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)data;

	if (!ieee80211_is_data_qos(hdr->frame_control))
		return RX_CONTINUE;

	/* remove the qos control field, update frame type and meta-data */
	memmove(data + IEEE80211_QOS_CTL_LEN, data,
		ieee80211_hdrlen(hdr->frame_control) - IEEE80211_QOS_CTL_LEN);
	hdr = (struct ieee80211_hdr *)atbm_skb_pull(rx->skb, IEEE80211_QOS_CTL_LEN);
	/* change frame type to non QOS */
	hdr->frame_control &= ~cpu_to_le16(IEEE80211_STYPE_QOS_DATA);

	return RX_CONTINUE;
}

static int
ieee80211_802_1x_port_control(struct ieee80211_rx_data *rx)
{
	if (unlikely(!rx->sta ||
	    !test_sta_flag(rx->sta, WLAN_STA_AUTHORIZED)))
		return -EACCES;

	return 0;
}

static int
ieee80211_drop_unencrypted(struct ieee80211_rx_data *rx, __le16 fc)
{
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);

	/*
	 * Pass through unencrypted frames if the hardware has
	 * decrypted them already.
	 */
	if (status->flag & RX_FLAG_DECRYPTED)
		return 0;

	/* Drop unencrypted frames if key is set. */
	if (unlikely(!ieee80211_has_protected(fc) &&
		     !ieee80211_is_nullfunc(fc) &&
		     ieee80211_is_data(fc) &&
		     (rx->sta->enc)))
		return -EACCES;

	return 0;
}
static int
__ieee80211_data_to_8023(struct ieee80211_rx_data *rx, bool *port_control)
{
	struct atbm_vif *vif = rx->vif;
	int ret;

	*port_control = false;

	ret = ieee80211_data_to_8023(rx->skb, vif->addr, vif->type);
	if (ret < 0)
		return ret;
	return 0;
}

/*
 * requires that rx->skb is a frame with ethernet header
 */
static bool ieee80211_frame_allowed(struct ieee80211_rx_data *rx, __le16 fc)
{
	if (ieee80211_802_1x_port_control(rx) ||
	    ieee80211_drop_unencrypted(rx, fc))
		return false;

	return true;
}
 /* TODO It should be removed before official delivery */
void dump_mem(u8 *data, int len)
 {
	 int i;

	 printk(KERN_ERR "dump_mem len %d\n ",len);
	 for (i = 0; i < len; i+=8) {
	 	if(len-i>=8){ 
			printk(KERN_ERR "%02x %02x %02x %02x |%02x %02x %02x %02x ", data[i], data[i+1], data[i+2], data[i+3], data[i+4], data[i+5], data[i+6], data[i+7]);
	 	}
		else if(len-i>=7){ 
			printk(KERN_ERR "%02x %02x %02x %02x |%02x %02x %02x  ", data[i], data[i+1], data[i+2], data[i+3], data[i+4], data[i+5], data[i+6]);
	 	}
		else if(len-i>=6){ 
			printk(KERN_ERR "%02x %02x %02x %02x |%02x %02x ", data[i], data[i+1], data[i+2], data[i+3], data[i+4], data[i+5]);
	 	}
		else if(len-i>=5){ 
			printk(KERN_ERR "%02x %02x %02x %02x |%02x ", data[i], data[i+1], data[i+2], data[i+3], data[i+4]);
	 	}
		else if(len-i>=4){ 
			printk(KERN_ERR "%02x %02x %02x %02x", data[i], data[i+1], data[i+2], data[i+3]);
	 	}
		else if(len-i>=3){ 
			printk(KERN_ERR "%02x %02x %02x ", data[i], data[i+1], data[i+2]);
	 	}
		else if(len-i>=2){ 
			printk(KERN_ERR "%02x %02x  ", data[i], data[i+1]);
	 	}
		else if(len-i>=2){ 
			printk(KERN_ERR "%02x  ", data[i]);
	 	}

	 }
	 printk(KERN_ERR "\n");
 }
/*
 * requires that rx->skb is a frame with ethernet header
 */
static void
ieee80211_deliver_skb(struct ieee80211_rx_data *rx)
{
	struct atbm_vif *vif = rx->vif;
	struct net_device *dev = vif->ndev;
	struct sk_buff *skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(rx->skb);

	skb = rx->skb;
	if (skb) {
		if (vif->type == NL80211_IFTYPE_STATION){
			if (!(status->flag & RX_FLAG_DECRYPTED)){
				if (vif->ap_info.enc){
					atbm_dev_kfree_skb(skb);
					return;
				}
			}
		}
		//dump_mem(skb->data,skb->len);
		skb->dev = dev;
		/* deliver to local stack */
		skb->protocol = eth_type_trans(skb, dev);
#ifdef CHKSUM_HW_SUPPORT
		if ((dev->features & NETIF_F_RXCSUM) &&(!(status->flag &RX_FLAG_HW_CHKSUM_ERROR))){
			skb->ip_summed=CHECKSUM_UNNECESSARY;
		}else{
			skb->ip_summed=CHECKSUM_NONE;
		}
#endif
		//printk(KERN_ERR "%s %d,skb->pkt_type  %x\n",__func__,__LINE__,skb->pkt_type );
		memset(skb->cb, 0, sizeof(skb->cb));
		atbm_netif_rx(skb);
	}
}

static int
atbm_ieee80211_amsdu_to_8023s(struct sk_buff *skb, struct sk_buff_head *list, 
	const u8 *addr, enum nl80211_iftype iftype, const unsigned int extra_headroom, bool has_80211_header)
{
	struct sk_buff *frame = NULL;
	u16 ethertype;
	u8 *payload;
	const struct ethhdr *eth;
	int remaining, err;
	u8 dst[ETH_ALEN], src[ETH_ALEN];

	if (has_80211_header){
		err = ieee80211_data_to_8023(skb, addr, iftype);
		if (err)
			goto out;
		eth = (struct ethhdr *)atbm_skb_pull(skb, sizeof(struct ethhdr));
		if (!eth)
			goto out;
	}
	else {
		eth = (struct ethhdr *)(skb->data);
	}

	while (skb != frame){
		u8 padding;
		u16 len = eth->h_proto;
		unsigned int subframe_len = sizeof(struct ethhdr)+ntohs(len);

		remaining = skb->len;
		memcpy(dst, eth->h_dest, ETH_ALEN);
		memcpy(src, eth->h_source, ETH_ALEN);

		padding = (4-subframe_len)&0x3;
		if (subframe_len > remaining)
			goto purge;
		if (atbm_compare_ether_addr(eth->h_dest, rfc1042_header))
			goto purge;

		atbm_skb_pull(skb, sizeof(struct ethhdr));
		if (remaining <= subframe_len + padding){
			frame = skb;
		}
		else {
			#ifdef LINUX_OS
			unsigned int hlen = ALIGN(extra_headroom, 4);
			#else
			unsigned int hlen = ALIGN2(extra_headroom, 4);
			#endif
			frame = atbm_dev_alloc_skb(hlen + subframe_len + 2);
			if (!frame)
				goto purge;

			atbm_skb_reserve(frame, hlen + sizeof(struct ethhdr) + 2);
			memcpy(atbm_skb_put(frame, ntohs(len)), skb->data, ntohs(len));

			eth = (struct ethhdr *)atbm_skb_pull(skb, ntohs(len) + padding);
			if (!eth){
				atbm_dev_kfree_skb(frame);
				goto purge;
			}
		}

		frame->priority = skb->priority;

		payload = frame->data;
		ethertype = (payload[6]<<8)|payload[7];

		if (likely((atbm_compare_ether_addr(payload, rfc1042_header) == 0 &&
				ethertype != ETH_P_AARP && ethertype != ETH_P_IPX) ||
				atbm_compare_ether_addr(payload, bridge_tunnel_header) == 0)){
			atbm_skb_pull(frame, 6);
			memcpy(atbm_skb_push(frame, ETH_ALEN), src, ETH_ALEN);
			memcpy(atbm_skb_push(frame, ETH_ALEN), dst, ETH_ALEN);
		}
		else {
			memcpy(atbm_skb_push(frame, sizeof(u16)), &len, sizeof(u16));
			memcpy(atbm_skb_push(frame, ETH_ALEN), src, ETH_ALEN);
			memcpy(atbm_skb_push(frame, ETH_ALEN), dst, ETH_ALEN);
		}
		atbm_skb_queue_tail(list, frame);
	}

	return 0;

purge:
	atbm_skb_queue_purge(list);
out:
	return -1;
}

static int
ieee80211_rx_h_amsdu(struct ieee80211_rx_data *rx)
{
	struct atbm_vif *vif = rx->vif;
	struct net_device *dev = vif->ndev;
	struct sk_buff *skb = rx->skb;
	struct sk_buff *frame;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)rx->skb->data;
	struct sk_buff_head frame_list;
	int err;

	if (unlikely(!ieee80211_is_data_present(hdr->frame_control)))
		return RX_DROP_MONITOR;

	if (is_multicast_ether_addr(hdr->addr1))
		return RX_DROP_UNUSABLE;

	if (status->flag & RX_FLAG_DECRYPTED){
		switch (rx->key->key_type){
			case IEEE80211_ENC_WEP:
			case IEEE80211_ENC_TKIP:
				return RX_DROP_UNUSABLE;
			default:
				break;
		}
	}

	if (vif->type == NL80211_IFTYPE_STATION){
		if (!(status->flag & RX_FLAG_DECRYPTED)){
			if (vif->ap_info.enc){
				return RX_DROP_UNUSABLE;
			}
		}
	}

	atbm_skb_queue_head_init(&frame_list);

	err = atbm_ieee80211_amsdu_to_8023s(skb, &frame_list, vif->addr, vif->type, 0, true);
	if (err)
		return RX_DROP_UNUSABLE;

	while (!atbm_skb_queue_empty(&frame_list)){
		frame = atbm_skb_dequeue(&frame_list);

		frame->dev = dev;
		frame->protocol = eth_type_trans(frame, dev);
#ifdef CHKSUM_HW_SUPPORT
		if ((dev->features & NETIF_F_RXCSUM) &&(!(status->flag &RX_FLAG_HW_CHKSUM_ERROR))){
			frame->ip_summed=CHECKSUM_UNNECESSARY;
		}else{
			frame->ip_summed=CHECKSUM_NONE;
		}
#endif
		memset(frame->cb, 0, sizeof(frame->cb));
		atbm_netif_rx(frame);
	}

	return 0;
}

static ieee80211_rx_result
ieee80211_rx_h_data(struct ieee80211_rx_data *rx)
{
	struct atbm_vif *vif = rx->vif;
	struct net_device *dev = vif->ndev;
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)rx->skb->data;
	__le16 fc = hdr->frame_control;
	bool port_control;
	int err;

	if (unlikely(!ieee80211_is_data(hdr->frame_control)))
		return RX_CONTINUE;

	if (unlikely(!ieee80211_is_data_present(hdr->frame_control)))
		return RX_DROP_MONITOR;

	if (status->rx_flags & IEEE80211_RX_AMSDU){
		err = ieee80211_rx_h_amsdu(rx);
		if (err)
			return RX_DROP_UNUSABLE;
		else {
			atbm_dev_kfree_skb(skb);
		}
	}
	else{
		err = __ieee80211_data_to_8023(rx, &port_control);
		if (unlikely(err)){
			atbm_printk_err("%s:to_8023 err\n",__func__);
			return RX_DROP_UNUSABLE;
		}
		if (!ieee80211_frame_allowed(rx, fc)){
			atbm_printk_err("%s:frame_allowed err\n",__func__);
			return RX_DROP_MONITOR;
		}
		rx->skb->dev = dev;

		dev->stats.rx_packets++;
		dev->stats.rx_bytes += rx->skb->len;
		ieee80211_deliver_skb(rx);
	}

	return RX_QUEUED;
}
static ieee80211_rx_result
ieee80211_rx_h_action(struct ieee80211_rx_data *rx)
{
	struct atbm_vif *vif = rx->vif;
	struct atbm_ieee80211_mgmt *mgmt = (struct atbm_ieee80211_mgmt *) rx->skb->data;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(rx->skb);
	int len = rx->skb->len;

	if (!ieee80211_is_action(mgmt->frame_control))
		return RX_CONTINUE;

	/* drop too small frames */
	if (len < IEEE80211_MIN_ACTION_SIZE)
		return RX_DROP_UNUSABLE;

	if (!rx->sta && mgmt->u.action.category != WLAN_CATEGORY_PUBLIC)
		return RX_DROP_UNUSABLE;

	if (!(status->rx_flags & IEEE80211_RX_RA_MATCH))
		return RX_DROP_UNUSABLE;

	switch (mgmt->u.action.category) {
	case WLAN_CATEGORY_BACK:
		/*
		 * The aggregation code is not prepared to handle
		 * anything but STA/AP due to the BSSID handling;
		 * IBSS could work in the code but isn't supported
		 * by drivers or the standard.
		 */
		if (vif->type != NL80211_IFTYPE_STATION &&
		    vif->type != NL80211_IFTYPE_AP_VLAN &&
		    vif->type != NL80211_IFTYPE_AP)
			break;

		/* verify action_code is present */
		if (len < IEEE80211_MIN_ACTION_SIZE + 1)
			break;

		switch (mgmt->u.action.u.addba_req.action_code) {
		case WLAN_ACTION_ADDBA_REQ:
			if (len < (IEEE80211_MIN_ACTION_SIZE +
				   sizeof(mgmt->u.action.u.addba_req)))
				goto invalid;
			break;
		case WLAN_ACTION_ADDBA_RESP:
			if (len < (IEEE80211_MIN_ACTION_SIZE +
				   sizeof(mgmt->u.action.u.addba_resp)))
				goto invalid;
			break;
		case WLAN_ACTION_DELBA:
			if (len < (IEEE80211_MIN_ACTION_SIZE +
				   sizeof(mgmt->u.action.u.delba)))
				goto invalid;
			break;
		default:
			goto invalid;
		}

		goto queue;	
	default:
		goto handled;
	}

	return RX_CONTINUE;

 invalid:
	status->rx_flags |= IEEE80211_RX_MALFORMED_ACTION_FRM;
	/* will return in the next handlers */
	return RX_CONTINUE;

 handled:
	atbm_dev_kfree_skb(rx->skb);
	return RX_QUEUED;
 queue:
	rx->skb->pkt_type = IEEE80211_SDATA_QUEUE_TYPE_FRAME;
	atbm_skb_queue_tail(&vif->skb_queue, rx->skb);
	atbm_hw_priv_queue_work(vif->hw_priv, &vif->work);
	return RX_QUEUED;
}
static void ieee80211_rx_handlers_result(struct ieee80211_rx_data *rx,
					 ieee80211_rx_result res)
{
	struct atbm_ieee80211_mgmt *mgmt;
	switch (res) {
	case RX_DROP_MONITOR:
		/* fall through */
	case RX_CONTINUE: 
	case RX_DROP_UNUSABLE:
		mgmt = (struct atbm_ieee80211_mgmt *)rx->skb->data;
		atbm_printk_err("%s:drop (%x)\n",__func__,mgmt->frame_control);
		atbm_dev_kfree_skb(rx->skb);
		break;
	case RX_QUEUED:
		break;
	}
}

ieee80211_rx_result
ieee80211_rx_h_michael_mic_verify(struct ieee80211_rx_data *rx)
{
	unsigned int hdrlen;
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)skb->data;

	if(rx->key == NULL)
		return RX_CONTINUE;
	
	if(rx->sta == NULL){
		return RX_CONTINUE;
	}

	if( !(status->flag & RX_FLAG_DECRYPTED)){
		return RX_CONTINUE;
	}

	if(IEEE80211_ENC_TKIP != rx->key->key_type)
		return RX_CONTINUE;
	/*
	 * it makes no sense to check for MIC errors on anything other
	 * than data frames.
	 */
	if (!ieee80211_is_data_present(hdr->frame_control))
		return RX_CONTINUE;

	/*
	 * No way to verify the MIC if the hardware stripped it or
	 * the IV with the key index. In this case we have solely rely
	 * on the driver to set RX_FLAG_MMIC_ERROR in the event of a
	 * MIC failure report.
	 */
	if (status->flag & (RX_FLAG_MMIC_STRIPPED | RX_FLAG_IV_STRIPPED)) {
		goto mic_fail;

	}
	
	if (status->flag & RX_FLAG_MMIC_ERROR)
		goto mic_fail;

	hdrlen = ieee80211_hdrlen(hdr->frame_control);
	if (skb->len < hdrlen + ATBM_MICHAEL_MIC_LEN)
		return RX_DROP_UNUSABLE;
	
	/* remove Michael MIC from payload */
	atbm_skb_trim(skb, skb->len - ATBM_MICHAEL_MIC_LEN);

	return RX_CONTINUE;

mic_fail:

	atbm_printk_debug("Mic Err\n");
	return RX_DROP_UNUSABLE;
}
static ieee80211_rx_result
ieee80211_rx_h_mgmt(struct ieee80211_rx_data *rx)
{
	struct atbm_vif *vif = rx->vif;
	struct atbm_ieee80211_mgmt *mgmt = (void *)rx->skb->data;
	__le16 stype;
	
	stype = mgmt->frame_control & cpu_to_le16(IEEE80211_FCTL_STYPE);

	switch (stype) {
	case cpu_to_le16(IEEE80211_STYPE_BEACON):
	case cpu_to_le16(IEEE80211_STYPE_PROBE_RESP):
		/* process for all: mesh, mlme, ibss */
		break;
	case cpu_to_le16(IEEE80211_STYPE_DEAUTH):
	case cpu_to_le16(IEEE80211_STYPE_DISASSOC):
		if (is_multicast_ether_addr(mgmt->da) &&
		    !is_broadcast_ether_addr(mgmt->da))
			return RX_DROP_MONITOR;

		/* process only for station */
		if (vif->type != NL80211_IFTYPE_STATION)
			return RX_DROP_MONITOR;
		break;
	case cpu_to_le16(IEEE80211_STYPE_PROBE_REQ):
	case cpu_to_le16(IEEE80211_STYPE_AUTH):
	case cpu_to_le16(IEEE80211_STYPE_ASSOC_RESP):
		break;
	default:
		return RX_DROP_MONITOR;
	}
	/* queue up frame and kick off work to process it */
	rx->skb->pkt_type = IEEE80211_SDATA_QUEUE_TYPE_FRAME;
	atbm_skb_queue_tail(&vif->skb_queue, rx->skb);
	atbm_hw_priv_queue_work(rx->hw_priv, &vif->work);

	return RX_QUEUED;
}

static void ieee80211_rx_handlers(struct ieee80211_rx_data *rx,struct sk_buff_head *frames)
{
	ieee80211_rx_result res = RX_DROP_MONITOR;
	struct sk_buff *skb;

#define CALL_RXH(rxh)			\
	do {				\
		res = rxh(rx);		\
		if (res != RX_CONTINUE)	\
			goto rxh_next;  \
	} while (0)
		
	spin_lock_bh(&rx->hw_priv->rx_path_lock);
	while ((skb = __atbm_skb_dequeue(frames))) {
		/*
		 * all the other fields are valid across frames
		 * that belong to an aMPDU since they are on the
		 * same TID from the same station
		 */
		rx->skb = skb;
		CALL_RXH(ieee80211_rx_h_decrypt);
		CALL_RXH(ieee80211_rx_h_sta_process);
		CALL_RXH(ieee80211_rx_h_michael_mic_verify);
		CALL_RXH(ieee80211_rx_h_remove_qos_control);
		CALL_RXH(ieee80211_rx_h_data);
		CALL_RXH(ieee80211_rx_h_action);
		CALL_RXH(ieee80211_rx_h_mgmt);
 rxh_next:
		ieee80211_rx_handlers_result(rx, res);
#undef CALL_RXH
	}
	spin_unlock_bh(&rx->hw_priv->rx_path_lock);
}

static void ieee80211_invoke_rx_handlers(struct ieee80211_rx_data *rx)
{
	ieee80211_rx_result res = RX_DROP_MONITOR;
	struct sk_buff_head reorder_release;
	
	__atbm_skb_queue_head_init(&reorder_release);
#define CALL_RXH(rxh)			\
	do {				\
		res = rxh(rx);		\
		if (res != RX_CONTINUE)	\
			goto rxh_next;  \
	} while (0)
	CALL_RXH(ieee80211_rx_h_check);
	ieee80211_rx_reorder_ampdu(rx,&reorder_release);
	ieee80211_rx_handlers(rx,&reorder_release);
	return;
 rxh_next:
	ieee80211_rx_handlers_result(rx, res);

#undef CALL_RXH
}

/*
 * This function makes calls into the RX path, therefore
 * it has to be invoked under RCU read lock.
 */
void ieee80211_release_reorder_timeout(struct sta_info *sta, int tid)
{
	struct ieee80211_rx_data rx = {
		.sta = sta,
		.vif = sta->vif,
		.hw_priv = sta->hw_priv,
		/* This is OK -- must be QoS data frame */
		.security_idx = tid,
		.seqno_idx = tid,
		.flags = 0,
	};
	struct tid_ampdu_rx *tid_agg_rx;
	struct sk_buff_head reorder_release;
	
	__atbm_skb_queue_head_init(&reorder_release);
	tid_agg_rx = rcu_dereference(sta->ampdu_mlme.tid_rx[tid]);
	if (!tid_agg_rx)
		return;

	spin_lock(&tid_agg_rx->reorder_lock);
	ieee80211_sta_reorder_release(sta->hw_priv, tid_agg_rx,&reorder_release);
	spin_unlock(&tid_agg_rx->reorder_lock);

	ieee80211_rx_handlers(&rx,&reorder_release);
}

/* main receive path */

static int prepare_for_handlers(struct ieee80211_rx_data *rx,
				struct ieee80211_hdr *hdr)
{
	struct atbm_vif *vif = rx->vif;
	struct sk_buff *skb = rx->skb;
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	u8 *bssid = ieee80211_get_bssid(hdr, skb->len, vif->type);
	int multicast = is_multicast_ether_addr(hdr->addr1);
	
	switch (vif->type) {
	case NL80211_IFTYPE_STATION:
		if (!bssid)
			return 0;
		if (!multicast &&
		    atbm_compare_ether_addr(vif->addr, hdr->addr1) != 0) {
			status->rx_flags &= ~IEEE80211_RX_RA_MATCH;
		}
		break;
	case NL80211_IFTYPE_AP_VLAN:
	case NL80211_IFTYPE_AP:
		break;
	default:
		/* should never get here */
		WARN_ON(1);
		return 0;
	}

	return 1;
}

/*
 * This function returns whether or not the SKB
 * was destined for RX processing or not, which,
 * if consume is true, is equivalent to whether
 * or not the skb was consumed.
 */
static bool ieee80211_prepare_and_rx_handle(struct ieee80211_rx_data *rx,
					    struct sk_buff *skb, bool consume)
{
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *hdr = (void *)skb->data;
	int prepares;

	rx->skb = skb;
	status->rx_flags |= IEEE80211_RX_RA_MATCH;
	prepares = prepare_for_handlers(rx, hdr);

	if (!prepares)
	{
		return false;
	}

	if (!consume) {
		skb = atbm_skb_copy(skb, GFP_ATOMIC);
		if (!skb) {
			if (net_ratelimit())
				atbm_printk_debug("failed to copy skb for\n");
			return true;
		}
		rx->skb = skb;
	}

	ieee80211_invoke_rx_handlers(rx);
	return true;
}

/*
 * This is the actual Rx frames handler. as it blongs to Rx path it must
 * be called with rcu_read_lock protection.
 */
static void __ieee80211_rx_handle_packet(struct atbm_vif *vif,
					 struct sk_buff *skb)
{
	struct atbm_common	*hw_priv = vif->hw_priv;
	struct ieee80211_hdr *hdr;
	__le16 fc;
	struct ieee80211_rx_data rx;
	int err = 0;

	fc = ((struct ieee80211_hdr *)skb->data)->frame_control;
	
	memset(&rx, 0, sizeof(rx));
	rx.skb = skb;
	rx.hw_priv = hw_priv;
	rx.vif = vif;
	
	if (ieee80211_is_mgmt(fc))
		err = atbm_skb_linearize(skb);
	else
		err = !atbm_pskb_may_pull(skb, ieee80211_hdrlen(fc));

	if (err) {
		atbm_dev_kfree_skb(skb);
		return;
	}

	hdr = (struct ieee80211_hdr *)skb->data;
	ieee80211_parse_qos(&rx);
	ieee80211_verify_alignment(&rx);

	rx.sta = sta_info_get_rx(vif,hdr->addr2);

	if(rx.sta == NULL){
		atbm_printk_err("%s: mac[%pM] not associate\n",__func__,hdr->addr2);
	}

	if(ieee80211_prepare_and_rx_handle(&rx,skb,true) == true)
		return;
	atbm_dev_kfree_skb(skb);
}

/*
 * This is the receive path handler. It is called by a low level driver when an
 * 802.11 MPDU is received from the hardware.
 */
void ieee80211_rx(struct atbm_vif *vif, struct sk_buff *skb)
{
	struct ieee80211_rx_status *status = IEEE80211_SKB_RXCB(skb);

	WARN_ON_ONCE(softirq_count() == 0);

	status->rx_flags = 0;

	/*
	 * key references and virtual interfaces are protected using RCU
	 * and this requires that we are in a read-side RCU section during
	 * receive processing
	 */
	rcu_read_lock();
	skb->pkt_type = 0;
	__ieee80211_rx_handle_packet(vif, skb);
	rcu_read_unlock();

	return;
}
