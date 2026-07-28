/*
 * Copyright 2002-2005, Instant802 Networks, Inc.
 * Copyright 2005-2006, Devicescape Software, Inc.
 * Copyright 2006-2007	Jiri Benc <jbenc@suse.cz>
 * Copyright 2007	Johannes Berg <johannes@sipsolutions.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 *
 * Transmit and frame generation functions.
 */

#include <linux/kernel.h>
#include <linux/slab.h>
#include <linux/skbuff.h>
#include <linux/etherdevice.h>
#include <linux/bitmap.h>
#include <linux/rcupdate.h>
#include <linux/export.h>
#include <net/net_namespace.h>
#include <net/ieee80211_radiotap.h>
#include <net/cfg80211.h>
#include <net/atbm_mac80211.h>
#include <asm/unaligned.h>
#include <linux/udp.h>
#include <net/ip.h>


#include "ieee80211_i.h"
#include "driver-ops.h"
#include "led.h"
#include "mesh.h"
#include "wep.h"
#include "wpa.h"
#include "wapi.h"
#include "wme.h"
#include "rate.h"

/* misc utils */
extern int Atbm_Test_Success;
extern struct test_threshold gthreshold_param;
#ifdef CONFIG_ATBM_MAC80211_NO_USE
static __le16 ieee80211_duration(struct ieee80211_tx_data *tx, int group_addr,
				 int next_frag_len)
{
	int rate, mrate, erp, dur, i;
	struct ieee80211_rate *txrate;
	struct ieee80211_local *local = tx->local;
	struct ieee80211_supported_band *sband;
	struct ieee80211_hdr *hdr;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);

	/* assume HW handles this */
	if (info->control.rates[0].flags & IEEE80211_TX_RC_MCS)
		return 0;

	/* uh huh? */
	if (WARN_ON_ONCE(info->control.rates[0].idx < 0))
		return 0;

	sband = local->hw.wiphy->bands[tx->channel->band];
	txrate = &sband->bitrates[info->control.rates[0].idx];

	erp = txrate->flags & IEEE80211_RATE_ERP_G;

	/*
	 * data and mgmt (except PS Poll):
	 * - during CFP: 32768
	 * - during contention period:
	 *   if addr1 is group address: 0
	 *   if more fragments = 0 and addr1 is individual address: time to
	 *      transmit one ACK plus SIFS
	 *   if more fragments = 1 and addr1 is individual address: time to
	 *      transmit next fragment plus 2 x ACK plus 3 x SIFS
	 *
	 * IEEE 802.11, 9.6:
	 * - control response frame (CTS or ACK) shall be transmitted using the
	 *   same rate as the immediately previous frame in the frame exchange
	 *   sequence, if this rate belongs to the PHY mandatory rates, or else
	 *   at the highest possible rate belonging to the PHY rates in the
	 *   BSSBasicRateSet
	 */
	hdr = (struct ieee80211_hdr *)tx->skb->data;
	if (ieee80211_is_ctl(hdr->frame_control)) {
		/* TODO: These control frames are not currently sent by
		 * mac80211, but should they be implemented, this function
		 * needs to be updated to support duration field calculation.
		 *
		 * RTS: time needed to transmit pending data/mgmt frame plus
		 *    one CTS frame plus one ACK frame plus 3 x SIFS
		 * CTS: duration of immediately previous RTS minus time
		 *    required to transmit CTS and its SIFS
		 * ACK: 0 if immediately previous directed data/mgmt had
		 *    more=0, with more=1 duration in ACK frame is duration
		 *    from previous frame minus time needed to transmit ACK
		 *    and its SIFS
		 * PS Poll: BIT(15) | BIT(14) | aid
		 */
		return 0;
	}

	/* data/mgmt */
	if (0 /* FIX: data/mgmt during CFP */)
		return cpu_to_le16(32768);

	if (group_addr) /* Group address as the destination - no ACK */
		return 0;

	/* Individual destination address:
	 * IEEE 802.11, Ch. 9.6 (after IEEE 802.11g changes)
	 * CTS and ACK frames shall be transmitted using the highest rate in
	 * basic rate set that is less than or equal to the rate of the
	 * immediately previous frame and that is using the same modulation
	 * (CCK or OFDM). If no basic rate set matches with these requirements,
	 * the highest mandatory rate of the PHY that is less than or equal to
	 * the rate of the previous frame is used.
	 * Mandatory rates for IEEE 802.11g PHY: 1, 2, 5.5, 11, 6, 12, 24 Mbps
	 */
	rate = -1;
	/* use lowest available if everything fails */
	mrate = sband->bitrates[0].bitrate;
	for (i = 0; i < sband->n_bitrates; i++) {
		struct ieee80211_rate *r = &sband->bitrates[i];

		if (r->bitrate > txrate->bitrate)
			break;

		if (tx->sdata->vif.bss_conf.basic_rates & BIT(i))
			rate = r->bitrate;

		switch (sband->band) {
		case IEEE80211_BAND_2GHZ: {
			u32 flag;
			if (tx->sdata->flags & IEEE80211_SDATA_OPERATING_GMODE)
				flag = IEEE80211_RATE_MANDATORY_G;
			else
				flag = IEEE80211_RATE_MANDATORY_B;
			if (r->flags & flag)
				mrate = r->bitrate;
			break;
		}
		case IEEE80211_BAND_5GHZ:
			if (r->flags & IEEE80211_RATE_MANDATORY_A)
				mrate = r->bitrate;
			break;
		case IEEE80211_NUM_BANDS:
			WARN_ON(1);
			break;
		default:
			break;
		}
	}
	if (rate == -1) {
		/* No matching basic rate found; use highest suitable mandatory
		 * PHY rate */
		rate = mrate;
	}

	/* Time needed to transmit ACK
	 * (10 bytes + 4-byte FCS = 112 bits) plus SIFS; rounded up
	 * to closest integer */

	dur = ieee80211_frame_duration(sband->band, 10, rate, erp,
				tx->sdata->vif.bss_conf.use_short_preamble);

	if (next_frag_len) {
		/* Frame is fragmented: duration increases with time needed to
		 * transmit next fragment plus ACK and 2 x SIFS. */
		dur *= 2; /* ACK + SIFS */
		/* next fragment */
		dur += ieee80211_frame_duration(sband->band, next_frag_len,
				txrate->bitrate, erp,
				tx->sdata->vif.bss_conf.use_short_preamble);
	}

	return cpu_to_le16(dur);
}
static inline int is_ieee80211_device(struct ieee80211_local *local,
				      struct net_device *dev)
{
	return local == wdev_priv(dev->ieee80211_ptr);
}
/* tx handlers */
static ieee80211_tx_result debug_noinline
ieee80211_tx_h_dynamic_ps(struct ieee80211_tx_data *tx)
{
	struct ieee80211_local *local = tx->local;
	struct ieee80211_if_managed *ifmgd;

	/* driver doesn't support power save */
	if (!(local->hw.flags & IEEE80211_HW_SUPPORTS_PS))
		return TX_CONTINUE;

	/* hardware does dynamic power save */
	if (local->hw.flags & IEEE80211_HW_SUPPORTS_DYNAMIC_PS)
		return TX_CONTINUE;

	/* dynamic power save disabled */
	if (tx->sdata->vif.bss_conf.dynamic_ps_timeout <= 0)
		return TX_CONTINUE;

	/* we are scanning, don't enable power save */
	if (local->scanning)
		return TX_CONTINUE;

	if (!tx->sdata->ps_allowed)
		return TX_CONTINUE;

	/* No point if we're going to suspend */
	if (local->quiescing)
		return TX_CONTINUE;

	/* dynamic ps is supported only in managed mode */
	if (tx->sdata->vif.type != NL80211_IFTYPE_STATION)
		return TX_CONTINUE;

	ifmgd = &tx->sdata->u.mgd;

	/*
	 * Don't wakeup from power save if u-apsd is enabled, voip ac has
	 * u-apsd enabled and the frame is in voip class. This effectively
	 * means that even if all access categories have u-apsd enabled, in
	 * practise u-apsd is only used with the voip ac. This is a
	 * workaround for the case when received voip class packets do not
	 * have correct qos tag for some reason, due the network or the
	 * peer application.
	 *
	 * Note: local->uapsd_queues access is racy here. If the value is
	 * changed via debugfs, user needs to reassociate manually to have
	 * everything in sync.
	 */
	if ((ifmgd->flags & IEEE80211_STA_UAPSD_ENABLED)
	    && (local->uapsd_queues & IEEE80211_WMM_IE_STA_QOSINFO_AC_VO)
	    && skb_get_queue_mapping(tx->skb) == 0)
		return TX_CONTINUE;

	if (tx->sdata->vif.bss_conf.ps_enabled) {
		// XXX: update this to new queue locking API
		ieee80211_stop_queues_by_reason(&local->hw,
						IEEE80211_QUEUE_STOP_REASON_PS);
		ifmgd->flags &= ~IEEE80211_STA_NULLFUNC_ACKED;
		ieee80211_queue_work(&local->hw,
				     &tx->sdata->dynamic_ps_disable_work);
	}

	/* Don't restart the timer if we're not disassociated */
	if (!ifmgd->associated)
		return TX_CONTINUE;

	mod_timer(&tx->sdata->dynamic_ps_timer, jiffies +
		  msecs_to_jiffies(tx->sdata->vif.bss_conf.dynamic_ps_timeout));

	return TX_CONTINUE;
}
#endif
static ieee80211_tx_result debug_noinline
ieee80211_tx_h_check_assoc(struct ieee80211_tx_data *tx)
{

	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)tx->skb->data;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);
	bool assoc = false;

	if (unlikely(info->flags & IEEE80211_TX_CTL_INJECTED))
		return TX_CONTINUE;

	if (unlikely(test_bit(SCAN_OFF_CHANNEL, &tx->local->scanning)) &&
	    !ieee80211_is_probe_req(hdr->frame_control) &&
	    !ieee80211_is_nullfunc(hdr->frame_control))
		/*
		 * When software scanning only nullfunc frames (to notify
		 * the sleep state to the AP) and probe requests (for the
		 * active scan) are allowed, all other frames should not be
		 * sent and we should not get here, but if we do
		 * nonetheless, drop them to avoid sending them
		 * off-channel. See the link below and
		 * ieee80211_start_scan() for more.
		 *
		 * http://article.gmane.org/gmane.linux.kernel.wireless.general/30089
		 */
		return TX_DROP;
#ifdef CONFIG_ATBM_SUPPORT_WDS
	if (tx->sdata->vif.type == NL80211_IFTYPE_WDS)
		return TX_CONTINUE;
#endif
#ifdef CONFIG_MAC80211_ATBM_MESH
	if (tx->sdata->vif.type == NL80211_IFTYPE_MESH_POINT)
		return TX_CONTINUE;
#endif
	if (tx->flags & IEEE80211_TX_PS_BUFFERED)
		return TX_CONTINUE;

	if (tx->sta)
		assoc = test_sta_flag(tx->sta, WLAN_STA_ASSOC);

	if (likely(tx->flags & IEEE80211_TX_UNICAST)) {
		if (unlikely(!assoc &&
			     tx->sdata->vif.type != NL80211_IFTYPE_ADHOC &&
			     ieee80211_is_data(hdr->frame_control))) {
#ifdef CONFIG_MAC80211_ATBM_VERBOSE_DEBUG
			atbm_printk_debug( "%s: dropped data frame to not "
			       "associated station %pM\n",
			       tx->sdata->name, hdr->addr1);
#endif /* CONFIG_MAC80211_ATBM_VERBOSE_DEBUG */
			I802_DEBUG_INC(tx->local->tx_handlers_drop_not_assoc);
			return TX_DROP;
		}
	} else {
		if (unlikely(ieee80211_is_data(hdr->frame_control) &&
			     tx->local->num_sta == 0 &&
			     tx->sdata->vif.type != NL80211_IFTYPE_ADHOC)) {
			/*
			 * No associated STAs - no need to send multicast
			 * frames.
			 */
			return TX_DROP;
		}
		return TX_CONTINUE;
	}

	return TX_CONTINUE;
}

/* This function is called whenever the AP is about to exceed the maximum limit
 * of buffered frames for power saving STAs. This situation should not really
 * happen often during normal operation, so dropping the oldest buffered packet
 * from each queue should be OK to make some room for new frames. */
static void purge_old_ps_buffers(struct ieee80211_local *local)
{
	int total = 0, purged = 0;
	struct sk_buff *skb;
	struct ieee80211_sub_if_data *sdata;
	struct sta_info *sta;

	/*
	 * virtual interfaces are protected by RCU
	 */
	rcu_read_lock();

	list_for_each_entry_rcu(sdata, &local->interfaces, list) {
		struct ieee80211_if_ap *ap;
		if (sdata->vif.type != NL80211_IFTYPE_AP)
			continue;
		ap = &sdata->u.ap;
		skb = atbm_skb_dequeue(&ap->ps_bc_buf);
		if (skb) {
			purged++;
			atbm_dev_kfree_skb(skb);
		}
		total += atbm_skb_queue_len(&ap->ps_bc_buf);
	}

	/*
	 * Drop one frame from each station from the lowest-priority
	 * AC that has frames at all.
	 */
	list_for_each_entry_rcu(sta, &local->sta_list, list) {
		int ac;

		for (ac = IEEE80211_AC_BK; ac >= IEEE80211_AC_VO; ac--) {
			skb = atbm_skb_dequeue(&sta->ps_tx_buf[ac]);
			total += atbm_skb_queue_len(&sta->ps_tx_buf[ac]);
			if (skb) {
				purged++;
				atbm_dev_kfree_skb(skb);
				break;
			}
		}
	}

	rcu_read_unlock();

	local->total_ps_buffered = total;
#ifdef CONFIG_MAC80211_ATBM_VERBOSE_PS_DEBUG
	wiphy_debug(local->hw.wiphy, "PS buffers full - purged %d frames\n",
		    purged);
#endif
}

static ieee80211_tx_result
ieee80211_tx_h_multicast_ps_buf(struct ieee80211_tx_data *tx)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)tx->skb->data;

	/*
	 * broadcast/multicast frame
	 *
	 * If any of the associated stations is in power save mode,
	 * the frame is buffered to be sent after DTIM beacon frame.
	 * This is done either by the hardware or us.
	 */

	/* powersaving STAs only in AP/VLAN mode */
	if (!tx->sdata->bss)
		return TX_CONTINUE;

	/* no buffering for ordered frames */
	if (ieee80211_has_order(hdr->frame_control))
		return TX_CONTINUE;

	/* no stations in PS mode */
	if (!atomic_read(&tx->sdata->bss->num_sta_ps))
		return TX_CONTINUE;

	info->flags |= IEEE80211_TX_CTL_SEND_AFTER_DTIM;
	if (tx->local->hw.flags & IEEE80211_HW_QUEUE_CONTROL)
		info->hw_queue = tx->sdata->vif.cab_queue;

	/* device releases frame after DTIM beacon */
	if (!(tx->local->hw.flags & IEEE80211_HW_HOST_BROADCAST_PS_BUFFERING))
		return TX_CONTINUE;

	/* buffered in mac80211 */
	if (tx->local->total_ps_buffered >= TOTAL_MAX_TX_BUFFER)
		purge_old_ps_buffers(tx->local);

	if (atbm_skb_queue_len(&tx->sdata->bss->ps_bc_buf) >= AP_MAX_BC_BUFFER) {
#ifdef CONFIG_MAC80211_ATBM_VERBOSE_PS_DEBUG
		if (net_ratelimit())
			atbm_printk_debug("%s: BC TX buffer full - dropping the oldest frame\n",
			       tx->sdata->name);
#endif
		atbm_dev_kfree_skb(atbm_skb_dequeue(&tx->sdata->bss->ps_bc_buf));
	} else
		tx->local->total_ps_buffered++;

	atbm_skb_queue_tail(&tx->sdata->bss->ps_bc_buf, tx->skb);

	return TX_QUEUED;
}

static int ieee80211_use_mfp(__le16 fc, struct sta_info *sta,
			     struct sk_buff *skb)
{
	if (!ieee80211_is_mgmt(fc))
		return 0;

	if (sta == NULL || !test_sta_flag(sta, WLAN_STA_MFP))
		return 0;
	#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,15,0))
	if (!ieee80211_is_robust_mgmt_frame((struct ieee80211_hdr *)
					    skb->data))
	#else
	if (!ieee80211_is_robust_mgmt_frame(skb))
	#endif
		return 0;

	return 1;
}

static ieee80211_tx_result debug_noinline
ieee80211_tx_h_ps_buf(struct ieee80211_tx_data *tx)
{
	if (unlikely(tx->flags & IEEE80211_TX_PS_BUFFERED))
		return TX_CONTINUE;

	if (tx->flags & IEEE80211_TX_UNICAST)
		return ieee80211_tx_h_unicast_ps_buf(tx);
	else
		return ieee80211_tx_h_multicast_ps_buf(tx);
}

static ieee80211_tx_result debug_noinline
ieee80211_tx_h_check_control_port_protocol(struct ieee80211_tx_data *tx)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);

	if (unlikely(tx->sdata->control_port_protocol == tx->skb->protocol &&
		     tx->sdata->control_port_no_encrypt))
		info->flags |= IEEE80211_TX_INTFL_DONT_ENCRYPT;

	return TX_CONTINUE;
}

static ieee80211_tx_result debug_noinline
ieee80211_tx_h_select_key(struct ieee80211_tx_data *tx)
{
	struct ieee80211_key *key = NULL;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)tx->skb->data;

	if (unlikely(info->flags & IEEE80211_TX_INTFL_DONT_ENCRYPT))
		tx->key = NULL;
	else if (tx->sta && (key = rcu_dereference(tx->sta->ptk)))
		tx->key = key;
	else if (ieee80211_is_mgmt(hdr->frame_control) &&
		 is_multicast_ether_addr(hdr->addr1) &&
		 #if (LINUX_VERSION_CODE < KERNEL_VERSION(3,15,0))
		 ieee80211_is_robust_mgmt_frame(hdr) 
		 #else
		ieee80211_is_robust_mgmt_frame(tx->skb) 
		 #endif
		 &&
		 (key = rcu_dereference(tx->sdata->default_mgmt_key)))
		tx->key = key;
	else if (is_multicast_ether_addr(hdr->addr1) &&
		 (key = rcu_dereference(tx->sdata->default_multicast_key)))
		tx->key = key;
	else if (!is_multicast_ether_addr(hdr->addr1) &&
		 (key = rcu_dereference(tx->sdata->default_unicast_key)))
		tx->key = key;
	else if (tx->sdata->drop_unencrypted &&
		 (tx->skb->protocol != tx->sdata->control_port_protocol) &&
		 !(info->flags & IEEE80211_TX_CTL_INJECTED) &&
		 (
		  #if (LINUX_VERSION_CODE < KERNEL_VERSION(3,15,0))
		 !ieee80211_is_robust_mgmt_frame(hdr) 
		 #else
		  !ieee80211_is_robust_mgmt_frame(tx->skb) 
		 #endif
		 ||
		  (ieee80211_is_action(hdr->frame_control) &&
		   tx->sta && test_sta_flag(tx->sta, WLAN_STA_MFP)))) {
		I802_DEBUG_INC(tx->local->tx_handlers_drop_unencrypted);
		return TX_DROP;
	} else
		tx->key = NULL;

	if (tx->key) {
		bool skip_hw = false;

		tx->key->tx_rx_count++;
		/* TODO: add threshold stuff again */

		switch (tx->key->conf.cipher) {
		case WLAN_CIPHER_SUITE_WEP40:
		case WLAN_CIPHER_SUITE_WEP104:
			if (ieee80211_is_auth(hdr->frame_control))
				break;
		case WLAN_CIPHER_SUITE_TKIP:
			if (!ieee80211_is_data_present(hdr->frame_control))
				tx->key = NULL;
			break;
		case WLAN_CIPHER_SUITE_CCMP:
			if (!ieee80211_is_data_present(hdr->frame_control) &&
			    !ieee80211_use_mfp(hdr->frame_control, tx->sta,
					       tx->skb))
				tx->key = NULL;
			else
				skip_hw = (tx->key->conf.flags &
					   IEEE80211_KEY_FLAG_SW_MGMT) &&
					ieee80211_is_mgmt(hdr->frame_control);
			break;
		case WLAN_CIPHER_SUITE_AES_CMAC:
			if (!ieee80211_is_mgmt(hdr->frame_control))
				tx->key = NULL;
			break;
#ifdef CONFIG_WAPI_SUPPORT
		case WLAN_CIPHER_SUITE_SMS4:
			if (tx->ethertype == ETH_P_WAPI)
				tx->key = NULL;
			break;
#endif
		}

		if (unlikely(tx->key && tx->key->flags & KEY_FLAG_TAINTED))
			return TX_DROP;

		if (!skip_hw && tx->key &&
		    tx->key->flags & KEY_FLAG_UPLOADED_TO_HARDWARE)
			info->control.hw_key = &tx->key->conf;
	}

	return TX_CONTINUE;
}
#ifndef CONFIG_RATE_HW_CONTROL
static ieee80211_tx_result debug_noinline
ieee80211_tx_h_rate_ctrl(struct ieee80211_tx_data *tx)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);
	struct ieee80211_hdr *hdr = (void *)tx->skb->data;
	struct ieee80211_supported_band *sband;
	struct ieee80211_rate *rate;
	int i;
	u32 len;
	bool inval = false, rts = false, short_preamble = false;
	struct ieee80211_tx_rate_control txrc;
	bool assoc = false;

	memset(&txrc, 0, sizeof(txrc));

	sband = tx->local->hw.wiphy->bands[tx->channel->band];

	len = min_t(u32, tx->skb->len + FCS_LEN,
			 tx->local->hw.wiphy->frag_threshold);

	/* set up the tx rate control struct we give the RC algo */
	txrc.hw = local_to_hw(tx->local);
	txrc.sband = sband;
	txrc.bss_conf = &tx->sdata->vif.bss_conf;
	txrc.skb = tx->skb;
	txrc.reported_rate.idx = -1;
	txrc.rate_idx_mask = tx->sdata->rc_rateidx_mask[tx->channel->band];
	if (txrc.rate_idx_mask == (1 << sband->n_bitrates) - 1)
		txrc.max_rate_idx = -1;
	else
		txrc.max_rate_idx = fls(txrc.rate_idx_mask) - 1;
	txrc.bss = (tx->sdata->vif.type == NL80211_IFTYPE_AP ||
		    tx->sdata->vif.type == NL80211_IFTYPE_ADHOC);

	/* set up RTS protection if desired */
	if (len > tx->sdata->vif.bss_conf.rts_threshold)
		txrc.rts = rts = true;

	/*
	 * Use short preamble if the BSS can handle it, but not for
	 * management frames unless we know the receiver can handle
	 * that -- the management frame might be to a station that
	 * just wants a probe response.
	 */
	if (tx->sdata->vif.bss_conf.use_short_preamble &&
	    (ieee80211_is_data(hdr->frame_control) ||
	     (tx->sta && test_sta_flag(tx->sta, WLAN_STA_SHORT_PREAMBLE))))
		txrc.short_preamble = short_preamble = true;

	if (tx->sta)
		assoc = test_sta_flag(tx->sta, WLAN_STA_ASSOC);

	/*
	 * Lets not bother rate control if we're associated and cannot
	 * talk to the sta. This should not happen.
	 */
	if (WARN(test_bit(SCAN_SW_SCANNING, &tx->local->scanning) && assoc &&
		 !rate_usable_index_exists(sband, &tx->sta->sta),
		 "%s: Dropped data frame as no usable bitrate found while "
		 "scanning and associated. Target station: "
		 "%pM on %d GHz band\n",
		 tx->sdata->name, hdr->addr1,
		 tx->channel->band ? 5 : 2))
		return TX_DROP;

	/*
	 * If we're associated with the sta at this point we know we can at
	 * least send the frame at the lowest bit rate.
	 */
	rate_control_get_rate(tx->sdata, tx->sta, &txrc);
	/*
	*if we are station mode and not associate with the ap
	*check the rate according to the ap basic rate
	*/
	while((tx->sdata->vif.type == NL80211_IFTYPE_STATION)&&
	   (ieee80211_is_mgmt(hdr->frame_control))&&(tx->sdata->u.mgd.associated == NULL)){
	   struct cfg80211_bss *cbss = NULL;
	   struct ieee80211_bss *bss = NULL;
	   int j = 0;
	   u32 suport_rates = 0;
	   int min_rate = INT_MAX, min_rate_index = -1;
	   
	   cbss = ieee80211_atbm_get_bss(tx->sdata->local->hw.wiphy,tx->channel,hdr->addr1,NULL,0,0,0);

	   if(cbss == NULL){
	   		break;
	   }

	   bss = (struct ieee80211_bss *)cbss->priv;

	   if(bss == NULL){
			ieee80211_atbm_put_bss(tx->sdata->local->hw.wiphy,cbss);
	   		break;
	   }
	   atbm_printk_mgmt("%s:supp_rates_len(%zu),rate_index(%d)\n",__func__,bss->supp_rates_len,info->control.rates[0].idx);
	  	for (i = 0; i < bss->supp_rates_len; i++) {
			int rate = (bss->supp_rates[i] & 0x7f) * 5;
	
			for (j = 0; j < sband->n_bitrates; j++) {
				if (sband->bitrates[j].bitrate == rate) {
					suport_rates |= BIT(j);
					
					if (rate < min_rate) {
						min_rate = rate;
						min_rate_index = j;
					}
					break;
				}
			}
		}
		
		atbm_printk_mgmt("%s:suport_rates(%x),rate_index(%d)\n",__func__,suport_rates,info->control.rates[0].idx);
		if(suport_rates == 0){
			ieee80211_atbm_put_bss(tx->sdata->local->hw.wiphy,cbss);
			break;
		}
	    if(!(suport_rates&BIT(info->control.rates[0].idx))){
			for(i = 0; i < IEEE80211_TX_MAX_RATES; i++) {
				info->control.rates[i].idx = -1;
				info->control.rates[i].flags = 0;
				info->control.rates[i].count = 1;
			}

			info->control.rates[0].idx = min_rate_index;
			info->control.rates[0].count = 5;
	    }
		ieee80211_atbm_put_bss(tx->sdata->local->hw.wiphy,cbss);
		break;
	}
	if (unlikely(info->control.rates[0].idx < 0))
		return TX_DROP;

	if (txrc.reported_rate.idx < 0) {
		txrc.reported_rate = info->control.rates[0];
		if (tx->sta && ieee80211_is_data(hdr->frame_control))
			tx->sta->last_tx_rate = txrc.reported_rate;
	} else if (tx->sta)
		tx->sta->last_tx_rate = txrc.reported_rate;

	if (unlikely(!info->control.rates[0].count))
		info->control.rates[0].count = 1;

	if (WARN_ON_ONCE((info->control.rates[0].count > 1) &&
			 (info->flags & IEEE80211_TX_CTL_NO_ACK)))
		info->control.rates[0].count = 1;

	if (is_multicast_ether_addr(hdr->addr1)) {
		/*
		 * XXX: verify the rate is in the basic rateset
		 */
		return TX_CONTINUE;
	}

	/*
	 * set up the RTS/CTS rate as the fastest basic rate
	 * that is not faster than the data rate
	 *
	 * XXX: Should this check all retry rates?
	 */
	if (!(info->control.rates[0].flags & IEEE80211_TX_RC_MCS)) {
		s8 baserate = 0;

		rate = &sband->bitrates[info->control.rates[0].idx];

		for (i = 0; i < sband->n_bitrates; i++) {
			/* must be a basic rate */
			if (!(tx->sdata->vif.bss_conf.basic_rates & BIT(i)))
				continue;
			/* must not be faster than the data rate */
			if (sband->bitrates[i].bitrate > rate->bitrate)
				continue;
			/* maximum */
			if (sband->bitrates[baserate].bitrate <
			     sband->bitrates[i].bitrate)
				baserate = i;
		}

		info->control.rts_cts_rate_idx = baserate;
	}

	for (i = 0; i < IEEE80211_TX_MAX_RATES; i++) {
		/*
		 * make sure there's no valid rate following
		 * an invalid one, just in case drivers don't
		 * take the API seriously to stop at -1.
		 */
		if (inval) {
			info->control.rates[i].idx = -1;
			continue;
		}
		if (info->control.rates[i].idx < 0) {
			inval = true;
			continue;
		}

		/*
		 * For now assume MCS is already set up correctly, this
		 * needs to be fixed.
		 */
		if (info->control.rates[i].flags & IEEE80211_TX_RC_MCS) {
			WARN_ON(info->control.rates[i].idx > 76);
			continue;
		}

		/* set up RTS protection if desired */
		if (rts)
			info->control.rates[i].flags |=
				IEEE80211_TX_RC_USE_RTS_CTS;

		/* RC is busted */
		if (WARN_ON_ONCE(info->control.rates[i].idx >=
				 sband->n_bitrates)) {
			info->control.rates[i].idx = -1;
			continue;
		}

		rate = &sband->bitrates[info->control.rates[i].idx];

		/* set up short preamble */
		if (short_preamble &&
		    rate->flags & IEEE80211_RATE_SHORT_PREAMBLE)
			info->control.rates[i].flags |=
				IEEE80211_TX_RC_USE_SHORT_PREAMBLE;

		/* set up G protection */
		if (!rts && tx->sdata->vif.bss_conf.use_cts_prot &&
		    rate->flags & IEEE80211_RATE_ERP_G)
			info->control.rates[i].flags |=
				IEEE80211_TX_RC_USE_CTS_PROTECT;
	}

	return TX_CONTINUE;
}
#endif
#ifdef CONFIG_ATBM_MAC80211_NO_USE
static ieee80211_tx_result debug_noinline
ieee80211_tx_h_sequence(struct ieee80211_tx_data *tx)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *)tx->skb->data;
	u16 *seq;
	u8 *qc;
	int tid;

	/*
	 * Packet injection may want to control the sequence
	 * number, if we have no matching interface then we
	 * neither assign one ourselves nor ask the driver to.
	 */
	if (unlikely(info->control.vif->type == NL80211_IFTYPE_MONITOR))
		return TX_CONTINUE;

	if (unlikely(ieee80211_is_ctl(hdr->frame_control)))
		return TX_CONTINUE;

	if (ieee80211_hdrlen(hdr->frame_control) < 24)
		return TX_CONTINUE;

	if (ieee80211_is_qos_nullfunc(hdr->frame_control))
		return TX_CONTINUE;

	/*
	 * Anything but QoS data that has a sequence number field
	 * (is long enough) gets a sequence number from the global
	 * counter.
	 */
	if (!ieee80211_is_data_qos(hdr->frame_control)) {
		/* driver should assign sequence number */
		info->flags |= IEEE80211_TX_CTL_ASSIGN_SEQ;
		/* for pure STA mode without beacons, we can do it */
		hdr->seq_ctrl = cpu_to_le16(tx->sdata->sequence_number);
		tx->sdata->sequence_number += 0x10;
		return TX_CONTINUE;
	}

	/*
	 * This should be true for injected/management frames only, for
	 * management frames we have set the IEEE80211_TX_CTL_ASSIGN_SEQ
	 * above since they are not QoS-data frames.
	 */
	if (!tx->sta)
		return TX_CONTINUE;

	/* include per-STA, per-TID sequence counter */

	qc = ieee80211_get_qos_ctl(hdr);
	tid = *qc & IEEE80211_QOS_CTL_TID_MASK;
	seq = &tx->sta->tid_seq[tid];

	hdr->seq_ctrl = cpu_to_le16(*seq);

	/* Increase the sequence number. */
	*seq = (*seq + 0x10) & IEEE80211_SCTL_SEQ;

	return TX_CONTINUE;
}

static int ieee80211_fragment(struct ieee80211_local *local,
			      struct sk_buff *skb, int hdrlen,
			      int frag_threshold)
{
	struct sk_buff *tail = skb, *tmp;
	int per_fragm = frag_threshold - hdrlen - FCS_LEN;
	int pos = hdrlen + per_fragm;
	int rem = skb->len - hdrlen - per_fragm;

	if (WARN_ON(rem < 0))
		return -EINVAL;

	while (rem) {
		int fraglen = per_fragm;

		if (fraglen > rem)
			fraglen = rem;
		rem -= fraglen;
		tmp = atbm_dev_alloc_skb(local->tx_headroom +
				    frag_threshold +
				    IEEE80211_ENCRYPT_HEADROOM +
				    IEEE80211_ENCRYPT_TAILROOM);
		if (!tmp)
			return -ENOMEM;
		tail->next = tmp;
		tail = tmp;
		atbm_skb_reserve(tmp, local->tx_headroom +
				 IEEE80211_ENCRYPT_HEADROOM);
		/* copy control information */
		memcpy(tmp->cb, skb->cb, sizeof(tmp->cb));
		skb_copy_queue_mapping(tmp, skb);
		tmp->priority = skb->priority;
		tmp->dev = skb->dev;

		/* copy header and data */
		memcpy(atbm_skb_put(tmp, hdrlen), skb->data, hdrlen);
		memcpy(atbm_skb_put(tmp, fraglen), skb->data + pos, fraglen);

		pos += fraglen;
	}

	skb->len = hdrlen + per_fragm;
	return 0;
}

static ieee80211_tx_result debug_noinline
ieee80211_tx_h_fragment(struct ieee80211_tx_data *tx)
{
	struct sk_buff *skb = tx->skb;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	struct ieee80211_hdr *hdr = (void *)skb->data;
	int frag_threshold = tx->local->hw.wiphy->frag_threshold;
	int hdrlen;
	int fragnum;

	if (info->flags & IEEE80211_TX_CTL_DONTFRAG)
		return TX_CONTINUE;

	if (tx->local->ops->set_frag_threshold)
		return TX_CONTINUE;

	/*
	 * Warn when submitting a fragmented A-MPDU frame and drop it.
	 * This scenario is handled in ieee80211_tx_prepare but extra
	 * caution taken here as fragmented ampdu may cause Tx stop.
	 */
	if (WARN_ON(info->flags & IEEE80211_TX_CTL_AMPDU))
		return TX_DROP;

	hdrlen = ieee80211_hdrlen(hdr->frame_control);

	/* internal error, why isn't DONTFRAG set? */
	if (WARN_ON(skb->len + FCS_LEN <= frag_threshold))
		return TX_DROP;

	/*
	 * Now fragment the frame. This will allocate all the fragments and
	 * chain them (using skb as the first fragment) to skb->next.
	 * During transmission, we will remove the successfully transmitted
	 * fragments from this list. When the low-level driver rejects one
	 * of the fragments then we will simply pretend to accept the skb
	 * but store it away as pending.
	 */
	if (ieee80211_fragment(tx->local, skb, hdrlen, frag_threshold))
		return TX_DROP;

	/* update duration/seq/flags of fragments */
	fragnum = 0;
	do {
		int next_len;
		const __le16 morefrags = cpu_to_le16(IEEE80211_FCTL_MOREFRAGS);

		hdr = (void *)skb->data;
		info = IEEE80211_SKB_CB(skb);

		if (skb->next) {
			hdr->frame_control |= morefrags;
			next_len = skb->next->len;
			/*
			 * No multi-rate retries for fragmented frames, that
			 * would completely throw off the NAV at other STAs.
			 */
			info->control.rates[1].idx = -1;
			info->control.rates[2].idx = -1;
			info->control.rates[3].idx = -1;
			info->control.rates[4].idx = -1;
			BUILD_BUG_ON(IEEE80211_TX_MAX_RATES != 5);
			info->flags &= ~IEEE80211_TX_CTL_RATE_CTRL_PROBE;
		} else {
			hdr->frame_control &= ~morefrags;
			next_len = 0;
		}
		hdr->duration_id = ieee80211_duration(tx, 0, next_len);
		hdr->seq_ctrl |= cpu_to_le16(fragnum & IEEE80211_SCTL_FRAG);
		fragnum++;
	} while ((skb = skb->next));

	return TX_CONTINUE;
}
#endif

static ieee80211_tx_result debug_noinline
ieee80211_tx_h_stats(struct ieee80211_tx_data *tx)
{
	struct sk_buff *skb = tx->skb;

	if (!tx->sta)
		return TX_CONTINUE;

	tx->sta->tx_packets++;
	do {
		tx->sta->tx_fragments++;
		tx->sta->tx_bytes += skb->len;
	} while ((skb = skb->next));

	return TX_CONTINUE;
}

static ieee80211_tx_result debug_noinline
ieee80211_tx_h_encrypt(struct ieee80211_tx_data *tx)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(tx->skb);

	if (!tx->key)
		return TX_CONTINUE;

	switch (tx->key->conf.cipher) {
#ifdef CONFIG_ATBM_USE_SW_ENC
	case WLAN_CIPHER_SUITE_WEP40:
	case WLAN_CIPHER_SUITE_WEP104:
		return ieee80211_crypto_wep_encrypt(tx);
	case WLAN_CIPHER_SUITE_TKIP:
		return ieee80211_crypto_tkip_encrypt(tx);
	case WLAN_CIPHER_SUITE_CCMP:
		return ieee80211_crypto_ccmp_encrypt(tx);
	case WLAN_CIPHER_SUITE_AES_CMAC:
		return ieee80211_crypto_aes_cmac_encrypt(tx);
#endif
	default:
		/* handle hw-only algorithm */
		if (info->control.hw_key) {
			ieee80211_tx_set_protected(tx);
			return TX_CONTINUE;
		}
		break;

	}

	return TX_DROP;
}
#ifndef CONFIG_RATE_HW_CONTROL
static ieee80211_tx_result debug_noinline
ieee80211_tx_h_calculate_duration(struct ieee80211_tx_data *tx)
{
	struct sk_buff *skb = tx->skb;
	struct ieee80211_hdr *hdr;
	int next_len;
	bool group_addr;

	do {
		hdr = (void *) skb->data;
		if (unlikely(ieee80211_is_pspoll(hdr->frame_control)))
			break; /* must not overwrite AID */
		next_len = skb->next ? skb->next->len : 0;
		group_addr = is_multicast_ether_addr(hdr->addr1);

		hdr->duration_id =
			ieee80211_duration(tx, group_addr, next_len);
	} while ((skb = skb->next));

	return TX_CONTINUE;
}
#endif
/* actual transmit path */
#ifdef CONFIG_ATBM_SW_AGGTX
static bool ieee80211_tx_prep_agg(struct ieee80211_tx_data *tx,
				  struct sk_buff *skb,
				  struct ieee80211_tx_info *info,
				  struct tid_ampdu_tx *tid_tx,
				  int tid)
{
	bool queued = false;

	if (test_bit(HT_AGG_STATE_OPERATIONAL, &tid_tx->state)) {
		info->flags |= IEEE80211_TX_CTL_AMPDU;
	} else if (test_bit(HT_AGG_STATE_WANT_START, &tid_tx->state)) {
		/*
		 * nothing -- this aggregation session is being started
		 * but that might still fail with the driver
		 */
	} else {
		spin_lock(&tx->sta->lock);
		/*
		 * Need to re-check now, because we may get here
		 *
		 *  1) in the window during which the setup is actually
		 *     already done, but not marked yet because not all
		 *     packets are spliced over to the driver pending
		 *     queue yet -- if this happened we acquire the lock
		 *     either before or after the splice happens, but
		 *     need to recheck which of these cases happened.
		 *
		 *  2) during session teardown, if the OPERATIONAL bit
		 *     was cleared due to the teardown but the pointer
		 *     hasn't been assigned NULL yet (or we loaded it
		 *     before it was assigned) -- in this case it may
		 *     now be NULL which means we should just let the
		 *     packet pass through because splicing the frames
		 *     back is already done.
		 */
		tid_tx = rcu_dereference_protected_tid_tx(tx->sta, tid);

		if (!tid_tx) {
			/* do nothing, let packet pass through */
		} else if (test_bit(HT_AGG_STATE_OPERATIONAL, &tid_tx->state)) {
			info->flags |= IEEE80211_TX_CTL_AMPDU;
		} else {
			queued = true;
			info->control.vif = &tx->sdata->vif;
			info->flags |= IEEE80211_TX_INTFL_NEED_TXPROCESSING;
			__atbm_skb_queue_tail(&tid_tx->pending, skb);
		}
		spin_unlock(&tx->sta->lock);
	}

	return queued;
}
#endif
/*
 * initialises @tx
 */
static ieee80211_tx_result
ieee80211_tx_prepare(struct ieee80211_sub_if_data *sdata,
		     struct ieee80211_tx_data *tx,
		     struct sk_buff *skb)
{
	struct ieee80211_local *local = sdata->local;
	struct ieee80211_channel_state *chan_state = ieee80211_get_channel_state(local, sdata);
	struct ieee80211_hdr *hdr;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	int hdrlen;

	memset(tx, 0, sizeof(*tx));
	tx->skb = skb;
	tx->local = local;
	tx->sdata = sdata;
	tx->channel = chan_state->conf.channel;

	/*
	 * If this flag is set to true anywhere, and we get here,
	 * we are doing the needed processing, so remove the flag
	 * now.
	 */
	info->flags &= ~IEEE80211_TX_INTFL_NEED_TXPROCESSING;

	hdr = (struct ieee80211_hdr *) skb->data;

	if (sdata->vif.type == NL80211_IFTYPE_AP_VLAN) {
		tx->sta = rcu_dereference(sdata->u.vlan.sta);
		if (!tx->sta && sdata->dev->ieee80211_ptr->use_4addr)
			return TX_DROP;
	} else if (info->flags & IEEE80211_TX_CTL_INJECTED) {
		tx->sta = sta_info_get_bss(sdata, hdr->addr1);
	}
	if (!tx->sta)
		tx->sta = sta_info_get(sdata, hdr->addr1);

#ifdef CONFIG_ATBM_SW_AGGTX
	if (tx->sta && ieee80211_is_data_qos(hdr->frame_control) &&
	    !ieee80211_is_qos_nullfunc(hdr->frame_control) &&
	    (local->hw.flags & IEEE80211_HW_AMPDU_AGGREGATION) &&
	    !(local->hw.flags & IEEE80211_HW_TX_AMPDU_SETUP_IN_HW)) {
		struct tid_ampdu_tx *tid_tx;
		u8 *qc;
		int tid;
		
		qc = ieee80211_get_qos_ctl(hdr);
		tid = *qc & IEEE80211_QOS_CTL_TID_MASK;

		tid_tx = rcu_dereference(tx->sta->ampdu_mlme.tid_tx[tid]);
		if (tid_tx) {
			bool queued;

			queued = ieee80211_tx_prep_agg(tx, skb, info,
						       tid_tx, tid);

			if (unlikely(queued))
				return TX_QUEUED;
		}
	}
#endif

	if (is_multicast_ether_addr(hdr->addr1)) {
		tx->flags &= ~IEEE80211_TX_UNICAST;
		info->flags |= IEEE80211_TX_CTL_NO_ACK;
	} else {
		tx->flags |= IEEE80211_TX_UNICAST;
		if (unlikely(local->wifi_wme_noack_test))
			info->flags |= IEEE80211_TX_CTL_NO_ACK;
		/*
		 * Flags are initialized to 0. Hence, no need to
		 * explicitly unset IEEE80211_TX_CTL_NO_ACK since
		 * it might already be set for injected frames.
		 */
	}

	if (!(info->flags & IEEE80211_TX_CTL_DONTFRAG)) {
		if (!(tx->flags & IEEE80211_TX_UNICAST) ||
		    skb->len + FCS_LEN <= local->hw.wiphy->frag_threshold ||
		    info->flags & IEEE80211_TX_CTL_AMPDU)
			info->flags |= IEEE80211_TX_CTL_DONTFRAG;
	}

	if (!tx->sta)
		info->flags |= IEEE80211_TX_CTL_CLEAR_PS_FILT;
	else if (test_and_clear_sta_flag(tx->sta, WLAN_STA_CLEAR_PS_FILT))
		info->flags |= IEEE80211_TX_CTL_CLEAR_PS_FILT;

	hdrlen = ieee80211_hdrlen(hdr->frame_control);
	if (skb->len > hdrlen + sizeof(rfc1042_header) + 2) {
		u8 *pos = &skb->data[hdrlen + sizeof(rfc1042_header)];
		tx->ethertype = (pos[0] << 8) | pos[1];
	}

	info->flags |= IEEE80211_TX_CTL_FIRST_FRAGMENT;	
	
	if(sdata->vif.type == NL80211_IFTYPE_STATION) {
		
		struct atbm_ieee802_1x_hdr *hdr_1x;
		struct atbm_wpa_eapol_key *key;
		u16 sta_key_info;
		u16 key_data_len;
		u8* sta_mic = NULL;
		/*
		*sta must has been alloced
		*/
		if(!tx->sta)
			return TX_CONTINUE;
		/*
		*mgmt nulldata and qosnulldata will not be process
		*/
		if((!ieee80211_is_data(hdr->frame_control))||ieee80211_is_nullfunc(hdr->frame_control)||
		   ieee80211_is_qos_nullfunc(hdr->frame_control)){
			return TX_CONTINUE;
		}
		/*
		*enc suite must be rsn or wpa
		*/
		if(!test_sta_flag(tx->sta,WLAN_STA_WPA_RSN)){
			return TX_CONTINUE;
		}
		/*
		*if 4way handshake has been proceed successfully,we flush handshake_buffed skb
		*and send the new skb
		*if 4/4 Pairwise was sending ,we pend the skb to the handshake_buffed list
		*/
		if(tx->ethertype != ETH_P_PAE){
			if(test_sta_flag(tx->sta,WLAN_STA_HANDSHAKE4OF4_SUCCESS)){
				struct sk_buff *buffed_skb = NULL;
				while((buffed_skb = atbm_skb_dequeue(&tx->sta->handshake_buffed))){
					struct ieee80211_tx_info *buffed_info = IEEE80211_SKB_CB(buffed_skb);
					atbm_printk_always("release buffed skb\n");
					buffed_info->flags |= IEEE80211_TX_INTFL_NEED_TXPROCESSING;
					ieee80211_add_pending_skb(local, buffed_skb);
				}
			}else if(test_sta_flag(tx->sta,WLAN_STA_HANDSHAKE4OF4_SENDING)){
				atbm_skb_queue_tail(&tx->sta->handshake_buffed,skb);
				atbm_printk_always("buffed handshake\n");
				return TX_QUEUED;
			}
			return TX_CONTINUE;
		}
		
		hdr_1x = (struct atbm_ieee802_1x_hdr *)skb_network_header(skb);		
		key = (struct atbm_wpa_eapol_key *) (hdr_1x + 1);
		sta_key_info = (key->key_info[0]<<8) | key->key_info[1];
		sta_mic = (u8*)(key+1);
		key_data_len = ((*(sta_mic+tx->sta->mic_len))<<8)|(*(sta_mic+tx->sta->mic_len+1));
		
		if(key_data_len>skb->len-(skb_network_header(skb)-skb->data)-sizeof(struct atbm_wpa_eapol_key)){
		   return TX_CONTINUE;	
		}
		
		if(sta_key_info&(BIT(11)|BIT(13))) {
			atbm_printk_mgmt("%s:SMK\n",sdata->name);
		}if(!(sta_key_info&BIT(3))) {
			atbm_printk_mgmt("%s:2/2 Group\n",sdata->name);
		}else if(key_data_len == 0 ||
		   (tx->sta->mic_len == 0 && (sta_key_info & BIT(12)) &&
		    key_data_len == 16)) {
		    set_sta_flag(tx->sta,WLAN_STA_HANDSHAKE4OF4_SENDING);
			clear_sta_flag(tx->sta,WLAN_STA_HANDSHAKE4OF4_SUCCESS);
			info->flags |= IEEE80211_TX_HANDSHAKE;
			info->flags |= IEEE80211_TX_INTFL_DONT_ENCRYPT;
			atbm_printk_mgmt("%s:4/4 Pairwise\n",sdata->name);
		}else {
			atbm_printk_mgmt("%s:2/4 Pairwise\n",sdata->name);
		}
	}
	return TX_CONTINUE;
}

/*
 * Returns false if the frame couldn't be transmitted but was queued instead.
 */
static bool __ieee80211_tx(struct ieee80211_local *local, struct sk_buff **skbp,
			   struct sta_info *sta, bool txpending)
{
	struct sk_buff *skb = *skbp, *next;
	struct ieee80211_tx_info *info;
	struct ieee80211_sub_if_data *sdata;
	unsigned long flags;
	int len;
	bool fragm = false;

	while (skb) {
#ifndef ATBM_WIFI_QUEUE_LOCK_BUG
		int q = skb_get_queue_mapping(skb);
		__le16 fc;
#else
		int q;
		__le16 fc;
		info = IEEE80211_SKB_CB(skb);
		q=info->hw_queue;
		BUG_ON(q>=IEEE80211_MAX_QUEUES);
#endif

		spin_lock_irqsave(&local->queue_stop_reason_lock, flags);
		if (local->queue_stop_reasons[q] ||
		    (!txpending && !atbm_skb_queue_empty(&local->pending[q]))) {
			/*
			 * Since queue is stopped, queue up frames for later
			 * transmission from the tx-pending tasklet when the
			 * queue is woken again.
			 */
			if(local->queue_stop_reasons[q])
				atbm_printk_always("queue[%d] has been locked\n",q);
			do {
				next = skb->next;
				skb->next = NULL;
				/*
				 * NB: If txpending is true, next must already
				 * be NULL since we must've gone through this
				 * loop before already; therefore we can just
				 * queue the frame to the head without worrying
				 * about reordering of fragments.
				 */
				if (unlikely(txpending))
					__atbm_skb_queue_head(&local->pending[q],
							 skb);
				else
					__atbm_skb_queue_tail(&local->pending[q],
							 skb);
			} while ((skb = next));

			spin_unlock_irqrestore(&local->queue_stop_reason_lock,
					       flags);
			return false;
		}
		spin_unlock_irqrestore(&local->queue_stop_reason_lock, flags);
#ifndef ATBM_WIFI_QUEUE_LOCK_BUG
		info = IEEE80211_SKB_CB(skb);
#endif

		if (fragm)
			info->flags &= ~(IEEE80211_TX_CTL_CLEAR_PS_FILT |
					 IEEE80211_TX_CTL_FIRST_FRAGMENT);

		next = skb->next;
		len = skb->len;

		if (next)
			info->flags |= IEEE80211_TX_CTL_MORE_FRAMES;

		sdata = vif_to_sdata(info->control.vif);

		switch (sdata->vif.type) {
		case NL80211_IFTYPE_MONITOR:
			if(local->monitor_sdata !=  sdata)
				info->control.vif = NULL;
			else 
				atbm_printk_debug("%s:monitor[%s] send\n",__func__,sdata->name);
			break;
		case NL80211_IFTYPE_AP_VLAN:
			info->control.vif = &container_of(sdata->bss,
				struct ieee80211_sub_if_data, u.ap)->vif;
			break;
		default:
			/* keep */
			break;
		}

		if (sta && sta->uploaded)
			info->control.sta = &sta->sta;
		else
			info->control.sta = NULL;

		fc = ((struct ieee80211_hdr *)skb->data)->frame_control;
		drv_tx(local, skb);

		ieee80211_tpt_led_trig_tx(local, fc, len);
		*skbp = skb = next;
		ieee80211_led_tx(local, 1);
		fragm = true;
	}

	return true;
}

/*
 * Invoke TX handlers, return 0 on success and non-zero if the
 * frame was dropped or queued.
 */
static int invoke_tx_handlers(struct ieee80211_tx_data *tx)
{
	struct sk_buff *skb = tx->skb;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	ieee80211_tx_result res = TX_DROP;

#define CALL_TXH(txh) \
	do {				\
		res = txh(tx);		\
		if (res != TX_CONTINUE)	\
			goto txh_done;	\
	} while (0)
#ifdef CONFIG_ATBM_MAC80211_NO_USE
	CALL_TXH(ieee80211_tx_h_dynamic_ps);
#endif
	CALL_TXH(ieee80211_tx_h_check_assoc);
	CALL_TXH(ieee80211_tx_h_ps_buf);
	CALL_TXH(ieee80211_tx_h_check_control_port_protocol);
	CALL_TXH(ieee80211_tx_h_select_key);
#ifndef CONFIG_RATE_HW_CONTROL
	if (!(tx->local->hw.flags & IEEE80211_HW_HAS_RATE_CONTROL))
		CALL_TXH(ieee80211_tx_h_rate_ctrl);
#endif
	if (unlikely(info->flags & IEEE80211_TX_INTFL_RETRANSMISSION))
		goto txh_done;
#ifdef CONFIG_ATBM_USE_SW_ENC
	CALL_TXH(ieee80211_tx_h_michael_mic_add);
#endif
#ifdef CONFIG_ATBM_MAC80211_NO_USE
	CALL_TXH(ieee80211_tx_h_sequence);
	CALL_TXH(ieee80211_tx_h_fragment);
#endif
	/* handlers after fragment must be aware of tx info fragmentation! */
	CALL_TXH(ieee80211_tx_h_stats);
	CALL_TXH(ieee80211_tx_h_encrypt);
#ifndef CONFIG_RATE_HW_CONTROL
	if (!(tx->local->hw.flags & IEEE80211_HW_HAS_RATE_CONTROL))
		CALL_TXH(ieee80211_tx_h_calculate_duration);
#endif
#undef CALL_TXH

 txh_done:
	if (unlikely(res == TX_DROP)) {
		I802_DEBUG_INC(tx->local->tx_handlers_drop);
		while (skb) {
			struct sk_buff *next;

			next = skb->next;
			atbm_dev_kfree_skb(skb);
			skb = next;
		}
		return -1;
	} else if (unlikely(res == TX_QUEUED)) {
		I802_DEBUG_INC(tx->local->tx_handlers_queued);
		return -1;
	}

	return 0;
}

/*
 * Returns false if the frame couldn't be transmitted but was queued instead.
 */
static bool ieee80211_tx(struct ieee80211_sub_if_data *sdata,
			 struct sk_buff *skb, bool txpending)
{
	struct ieee80211_local *local = sdata->local;
	struct ieee80211_channel_state *chan_state = ieee80211_get_channel_state(local, sdata);
	struct ieee80211_tx_data tx;
	ieee80211_tx_result res_prepare;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	bool result = true;

	if (unlikely(skb->len < 10)) {
		atbm_dev_kfree_skb(skb);
		return true;
	}

	rcu_read_lock();

	/* initialises tx */
	res_prepare = ieee80211_tx_prepare(sdata, &tx, skb);

	if (unlikely(res_prepare == TX_DROP)) {
		atbm_dev_kfree_skb(skb);
		goto out;
	} else if (unlikely(res_prepare == TX_QUEUED)) {
		goto out;
	}

	tx.channel = chan_state->conf.channel;
	info->band = tx.channel->band;

	/* set up hw_queue value early */
	if (!(info->flags & IEEE80211_TX_CTL_TX_OFFCHAN) ||
	    !(local->hw.flags & IEEE80211_HW_QUEUE_CONTROL))
		info->hw_queue =
			sdata->vif.hw_queue[skb_get_queue_mapping(skb)];

	if (!invoke_tx_handlers(&tx))
		result = __ieee80211_tx(local, &tx.skb, tx.sta, txpending);
 out:
	rcu_read_unlock();
	return result;
}

/* device xmit handlers */

static int ieee80211_skb_resize(struct ieee80211_sub_if_data *sdata,
				struct sk_buff *skb,
				int head_need, bool may_encrypt)
{
	struct ieee80211_local *local = sdata->local;
	int tail_need = 0;

	if (may_encrypt && sdata->crypto_tx_tailroom_needed_cnt) {
		tail_need = IEEE80211_ENCRYPT_TAILROOM;
		tail_need -= atbm_skb_tailroom(skb);
		tail_need = max_t(int, tail_need, 0);
	}

	if (atbm_skb_cloned(skb))
		I802_DEBUG_INC(local->tx_expand_skb_head_cloned);
	else if (head_need || tail_need)
		I802_DEBUG_INC(local->tx_expand_skb_head);
	else
		return 0;

	if (atbm_pskb_expand_head(skb, head_need, tail_need, GFP_ATOMIC)) {
		atbm_printk_debug("failed to reallocate TX buffer\n");
		return -ENOMEM;
	}

	return 0;
}
#ifdef ATBM_SPECIAL_PKG_DOWN_RATE
static void ieee80211_xmit_down_bootp_rate(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	#define IS_BOOTP_PORT(src_port,des_port) ((((src_port) == 67)&&((des_port) == 68)) || \
											   (((src_port) == 68)&&((des_port) == 67)))
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	struct iphdr *iph; //= ip_hdr(skb);
	struct udphdr *udph;
	
	iph = ip_hdr(skb);
	if(iph->protocol != IPPROTO_UDP)
		return;

	udph = (struct udphdr *)((u8*)iph+(iph->ihl)*4);
	if(!IS_BOOTP_PORT(ntohs(udph->source),ntohs(udph->dest)))
		return;
	atbm_printk_tx("[%s]:down_bootp_rate\n",sdata->name);
	info->flags |= IEEE80211_TX_CTL_USE_MINRATE;

	if(sdata->vif.p2p)
		info->flags |= IEEE80211_TX_CTL_NO_CCK_RATE;
	
}
static void ieee80211_xmit_down_eap_rate(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	atbm_printk_tx("[%s]:down_eap_rate\n",sdata->name);
	info->flags |= IEEE80211_TX_CTL_USE_MINRATE;

	if(sdata->vif.p2p)
		info->flags |= IEEE80211_TX_CTL_NO_CCK_RATE;
}
static void ieee80211_xmit_down_ipv6_rate(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	
	info->flags |= IEEE80211_TX_CTL_USE_MINRATE;
	if(sdata->vif.p2p)
		info->flags |= IEEE80211_TX_CTL_NO_CCK_RATE;
	
}

static void ieee80211_xmit_down_arp_rate(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	info->flags |= IEEE80211_TX_CTL_USE_MINRATE;
	if(sdata->vif.p2p)
		info->flags |= IEEE80211_TX_CTL_NO_CCK_RATE;
}

static void ieee80211_xmit_trydown_special_pkg_rate(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	#define ATBM_SNAP_SIZE  6
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *) skb->data;
	u16 ether_type = 0;
	u8 ether_type_index = 0;
	
	if(!ieee80211_is_data(hdr->frame_control))
		return;
	if(ieee80211_is_nullfunc(hdr->frame_control))
		return;
	if(ieee80211_is_qos_nullfunc(hdr->frame_control))
		return;
	
	ether_type_index = ieee80211_hdrlen(hdr->frame_control) + ATBM_SNAP_SIZE;
	ether_type = (skb->data[ether_type_index]<<8) | skb->data[ether_type_index+1];
	
	if(ether_type == ETH_P_ARP)
		ieee80211_xmit_down_arp_rate(sdata,skb);
	else if(ether_type == ETH_P_IP)
		ieee80211_xmit_down_bootp_rate(sdata,skb);
	else if(ether_type == ETH_P_PAE)
		ieee80211_xmit_down_eap_rate(sdata,skb);
	else if(ether_type == ETH_P_IPV6)
		ieee80211_xmit_down_ipv6_rate(sdata,skb);
	
}
#endif
void ieee80211_xmit(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	struct ieee80211_local *local = sdata->local;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
#ifdef CONFIG_MAC80211_ATBM_MESH
	struct ieee80211_hdr *hdr = (struct ieee80211_hdr *) skb->data;
#endif
	int headroom;
	bool may_encrypt;

	rcu_read_lock();

	may_encrypt = !(info->flags & IEEE80211_TX_INTFL_DONT_ENCRYPT);

	headroom = local->tx_headroom;
	if (may_encrypt)
		headroom += IEEE80211_ENCRYPT_HEADROOM;
	headroom -= atbm_skb_headroom(skb);
	headroom = max_t(int, 0, headroom);

	if (ieee80211_skb_resize(sdata, skb, headroom, may_encrypt)) {
		atbm_dev_kfree_skb(skb);
		rcu_read_unlock();
		return;
	}
	atbm_skb_tx_debug(skb);
	info->control.vif = &sdata->vif;
#ifdef CONFIG_MAC80211_ATBM_MESH
	hdr = (struct ieee80211_hdr *) skb->data;
	if (ieee80211_vif_is_mesh(&sdata->vif) &&
	    ieee80211_is_data(hdr->frame_control) &&
		!is_multicast_ether_addr(hdr->addr1))
			if (mesh_nexthop_lookup(skb, sdata)) {
				/* skb queued: don't free */
				rcu_read_unlock();
				return;
			}
#endif
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,27))
	/* Older kernels do not have the select_queue callback */
	atbm_skb_set_queue_mapping(skb, ieee80211_select_queue(sdata, skb));
#endif

	ieee80211_set_qos_hdr(sdata, skb);
#ifdef ATBM_SPECIAL_PKG_DOWN_RATE
	ieee80211_xmit_trydown_special_pkg_rate(sdata,skb);
#endif
	ieee80211_tx(sdata, skb, false);
	rcu_read_unlock();
}

static bool ieee80211_parse_tx_radiotap(struct sk_buff *skb)
{
	struct ieee80211_radiotap_iterator iterator;
	struct ieee80211_radiotap_header *rthdr =
		(struct ieee80211_radiotap_header *) skb->data;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	int ret = ieee80211_radiotap_iterator_init(&iterator, rthdr, skb->len,
						   NULL);
	u16 txflags;

	info->flags |= IEEE80211_TX_INTFL_DONT_ENCRYPT |
		       IEEE80211_TX_CTL_DONTFRAG;

	/*
	 * for every radiotap entry that is present
	 * (ieee80211_radiotap_iterator_next returns -ENOENT when no more
	 * entries present, or -EINVAL on error)
	 */

	while (!ret) {
		ret = ieee80211_radiotap_iterator_next(&iterator);

		if (ret)
			continue;

		/* see if this argument is something we can use */
		switch (iterator.this_arg_index) {
		/*
		 * You must take care when dereferencing iterator.this_arg
		 * for multibyte types... the pointer is not aligned.  Use
		 * get_unaligned((type *)iterator.this_arg) to dereference
		 * iterator.this_arg for type "type" safely on all arches.
		*/
		case IEEE80211_RADIOTAP_FLAGS:
			if (*iterator.this_arg & IEEE80211_RADIOTAP_F_FCS) {
				/*
				 * this indicates that the skb we have been
				 * handed has the 32-bit FCS CRC at the end...
				 * we should react to that by snipping it off
				 * because it will be recomputed and added
				 * on transmission
				 */
				if (skb->len < (iterator._max_length + FCS_LEN))
					return false;

				atbm_skb_trim(skb, skb->len - FCS_LEN);
			}
			if (*iterator.this_arg & IEEE80211_RADIOTAP_F_WEP)
				info->flags &= ~IEEE80211_TX_INTFL_DONT_ENCRYPT;
			if (*iterator.this_arg & IEEE80211_RADIOTAP_F_FRAG)
				info->flags &= ~IEEE80211_TX_CTL_DONTFRAG;
			break;

		case IEEE80211_RADIOTAP_TX_FLAGS:
			txflags = get_unaligned_le16(iterator.this_arg);
			if (txflags & IEEE80211_RADIOTAP_F_TX_NOACK)
				info->flags |= IEEE80211_TX_CTL_NO_ACK;
			break;

		/*
		 * Please update the file
		 * Documentation/networking/mac80211-injection.txt
		 * when parsing new fields here.
		 */

		default:
			break;
		}
	}

	if (ret != -ENOENT) /* ie, if we didn't simply run out of fields */
		return false;

	/*
	 * remove the radiotap header
	 * iterator->_max_length was sanity-checked against
	 * skb->len by iterator init
	 */
	atbm_skb_pull(skb, iterator._max_length);

	return true;
}

static bool ieee80211_ap_can_xmit(struct net_device *dev)
{
	struct ieee80211_local *local = wdev_priv(dev->ieee80211_ptr);
	struct ieee80211_sub_if_data *sdata = IEEE80211_DEV_TO_SUB_IF(dev);
	struct ieee80211_channel_state *chan_state = ieee80211_get_channel_state(local, sdata);
	struct ieee80211_channel *chan = chan_state->conf.channel;
	bool can_xmit = true;
	
#ifndef CONFIG_ATBM_5G_PRETEND_2G
	if ((chan->flags & (
		#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,11,0))
		IEEE80211_CHAN_NO_IBSS |
		#endif
		IEEE80211_CHAN_RADAR |
	     #if (LINUX_VERSION_CODE < KERNEL_VERSION(3,11,0))
	     IEEE80211_CHAN_PASSIVE_SCAN
	     #else
	     IEEE80211_CHAN_NO_IR
	     #endif
	     )))
	    can_xmit = false;
		
#else
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 9, 0))
	struct cfg80211_chan_def chandef;
	cfg80211_chandef_create(&chandef,chan,vif_chw(&sdata->vif));
	can_xmit = cfg80211_reg_can_beacon(local->hw.wiphy,&chandef
			   #if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 16, 0))
		       ,sdata->vif.type
		       #endif
		       );
#else
	BUG_ON(chan == NULL);
	can_xmit = true;
#endif
#endif
	return can_xmit;
}
netdev_tx_t ieee80211_monitor_start_xmit(struct sk_buff *skb,
					 struct net_device *dev)
{
	struct ieee80211_local *local = wdev_priv(dev->ieee80211_ptr);
	struct ieee80211_sub_if_data *tmp_sdata, *sdata = IEEE80211_DEV_TO_SUB_IF(dev);
	struct ieee80211_radiotap_header *prthdr =
		(struct ieee80211_radiotap_header *)skb->data;
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	struct ieee80211_hdr *hdr;
	u16 len_rthdr;
	int hdrlen;
	bool monitor_relate = false;

	/*
	 * Frame injection is not allowed if beaconing is not allowed
	 * or if we need radar detection. Beaconing is usually not allowed when
	 * the mode or operation (Adhoc, AP, Mesh) does not support DFS.
	 * Passive scan is also used in world regulatory domains where
	 * your country is not known and as such it should be treated as
	 * NO TX unless the channel is explicitly allowed in which case
	 * your current regulatory domain would not have the passive scan
	 * flag.
	 *
	 * Since AP mode uses monitor interfaces to inject/TX management
	 * frames we can make AP mode the exception to this rule once it
	 * supports radar detection as its implementation can deal with
	 * radar detection by itself. We can do that later by adding a
	 * monitor flag interfaces used for AP support.
	 */
	#if 0
	if ((chan->flags & (
		#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,11,0))
		IEEE80211_CHAN_NO_IBSS |
		#endif
		IEEE80211_CHAN_RADAR |
	     #if (LINUX_VERSION_CODE < KERNEL_VERSION(3,11,0))
	     IEEE80211_CHAN_PASSIVE_SCAN
	     #else
	     IEEE80211_CHAN_NO_IR
	     #endif
	     )))
		goto fail;
	#endif
	if(ieee80211_ap_can_xmit(dev)==false)
		goto fail;
	/* check for not even having the fixed radiotap header part */
	if (unlikely(skb->len < sizeof(struct ieee80211_radiotap_header)))
		goto fail; /* too short to be possibly valid */

	/* is it a header version we can trust to find length from? */
	if (unlikely(prthdr->it_version))
		goto fail; /* only version 0 is supported */

	/* then there must be a radiotap header with a length we can use */
	len_rthdr = ieee80211_get_radiotap_len(skb->data);

	/* does the skb contain enough to deliver on the alleged length? */
	if (unlikely(skb->len < len_rthdr))
		goto fail; /* skb too short for claimed rt header extent */

	/*
	 * fix up the pointers accounting for the radiotap
	 * header still being in there.  We are being given
	 * a precooked IEEE80211 header so no need for
	 * normal processing
	 */
	atbm_skb_set_mac_header(skb, len_rthdr);
	/*
	 * these are just fixed to the end of the rt area since we
	 * don't have any better information and at this point, nobody cares
	 */
	atbm_skb_set_network_header(skb, len_rthdr);
	atbm_skb_set_transport_header(skb, len_rthdr);

	if (skb->len < len_rthdr + 2)
		goto fail;

	hdr = (struct ieee80211_hdr *)(skb->data + len_rthdr);
	hdrlen = ieee80211_hdrlen(hdr->frame_control);

	if (skb->len < len_rthdr + hdrlen)
		goto fail;

	/*
	 * Initialize skb->protocol if the injected frame is a data frame
	 * carrying a rfc1042 header
	 */
	if (ieee80211_is_data(hdr->frame_control) &&
	    skb->len >= len_rthdr + hdrlen + sizeof(rfc1042_header) + 2) {
		u8 *payload = (u8 *)hdr + hdrlen;

		if (atbm_compare_ether_addr(payload, rfc1042_header) == 0)
			skb->protocol = cpu_to_be16((payload[6] << 8) |
						    payload[7]);
	}

	memset(info, 0, sizeof(*info));

	info->flags = IEEE80211_TX_CTL_REQ_TX_STATUS |
		      IEEE80211_TX_CTL_INJECTED;

	/* process and remove the injection radiotap header */
	if (!ieee80211_parse_tx_radiotap(skb))
		goto fail;

	rcu_read_lock();

	/*
	 * We process outgoing injected frames that have a local address
	 * we handle as though they are non-injected frames.
	 * This code here isn't entirely correct, the local MAC address
	 * isn't always enough to find the interface to use; for proper
	 * VLAN/WDS support we will need a different mechanism (which
	 * likely isn't going to be monitor interfaces).
	 */
	list_for_each_entry_rcu(tmp_sdata, &local->interfaces, list) {
		if (!ieee80211_sdata_running(tmp_sdata))
			continue;
		if(tmp_sdata == local->monitor_sdata){
			continue;
		}
		if (tmp_sdata->vif.type == NL80211_IFTYPE_MONITOR ||
		    tmp_sdata->vif.type == NL80211_IFTYPE_AP_VLAN ||
		    tmp_sdata->vif.type == NL80211_IFTYPE_WDS)
			continue;
		if (atbm_compare_ether_addr(tmp_sdata->vif.addr, hdr->addr2) == 0) {
			sdata = tmp_sdata;
			monitor_relate = true;
			break;
		}
	}
	if(monitor_relate == true){
		ieee80211_xmit(sdata, skb);
	}else {
		atbm_dev_kfree_skb(skb);
		atbm_printk_err( "%s:cannot find ralated sdata\n",sdata->name);
	}
	rcu_read_unlock();

	return NETDEV_TX_OK;

fail:
	atbm_dev_kfree_skb(skb);
	return NETDEV_TX_OK; /* meaning, we dealt with the skb */
}

/**
 * ieee80211_subif_start_xmit - netif start_xmit function for Ethernet-type
 * subinterfaces (wlan#, WDS, and VLAN interfaces)
 * @skb: packet to be sent
 * @dev: incoming interface
 *
 * Returns: 0 on success (and frees skb in this case) or 1 on failure (skb will
 * not be freed, and caller is responsible for either retrying later or freeing
 * skb).
 *
 * This function takes in an Ethernet header and encapsulates it with suitable
 * IEEE 802.11 header based on which interface the packet is coming in. The
 * encapsulated packet will then be passed to master interface, wlan#.11, for
 * transmission (through low-level driver).
 */
netdev_tx_t ieee80211_subif_start_xmit(struct sk_buff *skb,
				    struct net_device *dev)
{
	struct ieee80211_sub_if_data *sdata = IEEE80211_DEV_TO_SUB_IF(dev);
	struct ieee80211_local *local = sdata->local;
	struct ieee80211_tx_info *info;
	int ret = NETDEV_TX_BUSY, head_need;
	u16 ethertype, hdrlen,  meshhdrlen = 0;
	__le16 fc;
	struct ieee80211_hdr hdr;
	struct ieee80211s_hdr mesh_hdr __maybe_unused;
	struct mesh_path __maybe_unused *mppath = NULL;
	const u8 *encaps_data;
	int encaps_len, skip_header_bytes;
	int nh_pos, h_pos;
	struct sta_info *sta = NULL;
	bool wme_sta = false, authorized = false;
	struct sk_buff *tmp_skb;
#ifdef ATBM_SURPORT_TDLS
	bool tdls_direct = false;
	bool tdls_auth = false;
#endif

	if (unlikely(skb->len < ETH_HLEN)) {
		ret = NETDEV_TX_OK;
		goto fail;
	}
	
#ifdef CONFIG_MAC80211_BRIDGE
	{
		struct ieee80211_sub_if_data *tmp_sta = ieee80211_brigde_sdata_check(local,skb,sdata);

		if(tmp_sta != sdata){
			sdata = tmp_sta;
			dev = sdata->dev;
		}
	}
#endif
	/* convert Ethernet header to proper 802.11 header (based on
	 * operation mode) */
	ethertype = (skb->data[12] << 8) | skb->data[13];
	fc = cpu_to_le16(IEEE80211_FTYPE_DATA | IEEE80211_STYPE_DATA);

	switch (sdata->vif.type) {
	case NL80211_IFTYPE_AP_VLAN:
		rcu_read_lock();
		sta = rcu_dereference(sdata->u.vlan.sta);
		if (sta) {
			fc |= cpu_to_le16(IEEE80211_FCTL_FROMDS | IEEE80211_FCTL_TODS);
			/* RA TA DA SA */
			memcpy(hdr.addr1, sta->sta.addr, ETH_ALEN);
			memcpy(hdr.addr2, sdata->vif.addr, ETH_ALEN);
			memcpy(hdr.addr3, skb->data, ETH_ALEN);
			memcpy(hdr.addr4, skb->data + ETH_ALEN, ETH_ALEN);
			hdrlen = 30;
			authorized = test_sta_flag(sta, WLAN_STA_AUTHORIZED);
			wme_sta = test_sta_flag(sta, WLAN_STA_WME);
		}
		rcu_read_unlock();
		if (sta)
			break;
		/* fall through */
	case NL80211_IFTYPE_AP:
		fc |= cpu_to_le16(IEEE80211_FCTL_FROMDS);
		/* DA BSSID SA */
		memcpy(hdr.addr1, skb->data, ETH_ALEN);
		memcpy(hdr.addr2, sdata->vif.addr, ETH_ALEN);
		memcpy(hdr.addr3, skb->data + ETH_ALEN, ETH_ALEN);
		hdrlen = 24;
		break;
#ifdef CONFIG_ATBM_SUPPORT_WDS
	case NL80211_IFTYPE_WDS:
		fc |= cpu_to_le16(IEEE80211_FCTL_FROMDS | IEEE80211_FCTL_TODS);
		/* RA TA DA SA */
		memcpy(hdr.addr1, sdata->u.wds.remote_addr, ETH_ALEN);
		memcpy(hdr.addr2, sdata->vif.addr, ETH_ALEN);
		memcpy(hdr.addr3, skb->data, ETH_ALEN);
		memcpy(hdr.addr4, skb->data + ETH_ALEN, ETH_ALEN);
		hdrlen = 30;
		break;
#endif
#ifdef CONFIG_MAC80211_ATBM_MESH
	case NL80211_IFTYPE_MESH_POINT:
		if (!sdata->u.mesh.mshcfg.dot11MeshTTL) {
			/* Do not send frames with mesh_ttl == 0 */
			sdata->u.mesh.mshstats.dropped_frames_ttl++;
			ret = NETDEV_TX_OK;
			goto fail;
		}
		rcu_read_lock();
		if (!is_multicast_ether_addr(skb->data))
			mppath = mpp_path_lookup(skb->data, sdata);

		/*
		 * Use address extension if it is a packet from
		 * another interface or if we know the destination
		 * is being proxied by a portal (i.e. portal address
		 * differs from proxied address)
		 */
		if (atbm_compare_ether_addr(sdata->vif.addr,
				       skb->data + ETH_ALEN) == 0 &&
		    !(mppath && atbm_compare_ether_addr(mppath->mpp, skb->data))) {
			hdrlen = ieee80211_fill_mesh_addresses(&hdr, &fc,
					skb->data, skb->data + ETH_ALEN);
			rcu_read_unlock();
			meshhdrlen = ieee80211_new_mesh_header(&mesh_hdr,
					sdata, NULL, NULL);
		} else {
			int is_mesh_mcast = 1;
			const u8 *mesh_da;

			if (is_multicast_ether_addr(skb->data))
				/* DA TA mSA AE:SA */
				mesh_da = skb->data;
			else {
				static const u8 bcast[ETH_ALEN] =
					{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff };
				if (mppath) {
					/* RA TA mDA mSA AE:DA SA */
					mesh_da = mppath->mpp;
					is_mesh_mcast = 0;
				} else {
					/* DA TA mSA AE:SA */
					mesh_da = bcast;
				}
			}
			hdrlen = ieee80211_fill_mesh_addresses(&hdr, &fc,
					mesh_da, sdata->vif.addr);
			rcu_read_unlock();
			if (is_mesh_mcast)
				meshhdrlen =
					ieee80211_new_mesh_header(&mesh_hdr,
							sdata,
							skb->data + ETH_ALEN,
							NULL);
			else
				meshhdrlen =
					ieee80211_new_mesh_header(&mesh_hdr,
							sdata,
							skb->data,
							skb->data + ETH_ALEN);

		}
		break;
#endif
	case NL80211_IFTYPE_STATION:
#ifdef ATBM_SURPORT_TDLS
		#if (LINUX_VERSION_CODE > KERNEL_VERSION(3, 0, 8))
		if (sdata->wdev.wiphy->flags & WIPHY_FLAG_SUPPORTS_TDLS) {
			bool tdls_peer = false;

			rcu_read_lock();
			sta = sta_info_get(sdata, skb->data);
			if (sta) {
				authorized = test_sta_flag(sta,
							WLAN_STA_AUTHORIZED);
				wme_sta = test_sta_flag(sta, WLAN_STA_WME);
				tdls_peer = test_sta_flag(sta,
							 WLAN_STA_TDLS_PEER);
				tdls_auth = test_sta_flag(sta,
						WLAN_STA_TDLS_PEER_AUTH);
			}
			rcu_read_unlock();

			/*
			 * If the TDLS link is enabled, send everything
			 * directly. Otherwise, allow TDLS setup frames
			 * to be transmitted indirectly.
			 */
			tdls_direct = tdls_peer && (tdls_auth ||
				 !(ethertype == ETH_P_TDLS && skb->len > 14 &&
				   skb->data[14] == WLAN_TDLS_SNAP_RFTYPE));
		}
		#endif
		if (tdls_direct) {
			/* link during setup - throw out frames to peer */
			if (!tdls_auth) {
				ret = NETDEV_TX_OK;
				goto fail;
			}

			/* DA SA BSSID */
			memcpy(hdr.addr1, skb->data, ETH_ALEN);
			memcpy(hdr.addr2, skb->data + ETH_ALEN, ETH_ALEN);
			memcpy(hdr.addr3, sdata->u.mgd.bssid, ETH_ALEN);
			hdrlen = 24;
		}  else 
#endif
#ifdef CONFIG_ATBM_4ADDR
		if (sdata->u.mgd.use_4addr &&
			    cpu_to_be16(ethertype) != sdata->control_port_protocol) {
			fc |= cpu_to_le16(IEEE80211_FCTL_FROMDS |
					  IEEE80211_FCTL_TODS);
			/* RA TA DA SA */
			memcpy(hdr.addr1, sdata->u.mgd.bssid, ETH_ALEN);
			memcpy(hdr.addr2, sdata->vif.addr, ETH_ALEN);
			memcpy(hdr.addr3, skb->data, ETH_ALEN);
			memcpy(hdr.addr4, skb->data + ETH_ALEN, ETH_ALEN);
			hdrlen = 30;
		} else
#endif
		{
				
#ifdef CONFIG_MAC80211_BRIDGE
			if (ieee80211_brigde_change_txhdr(sdata,skb) == -1)
			{
				ret = NETDEV_TX_OK;
				goto fail;
			}
#endif	// CONFIG_MAC80211_BRIDGE
			fc |= cpu_to_le16(IEEE80211_FCTL_TODS);
			/* BSSID SA DA */
			memcpy(hdr.addr1, sdata->u.mgd.bssid, ETH_ALEN);
			memcpy(hdr.addr2, skb->data + ETH_ALEN, ETH_ALEN);
			memcpy(hdr.addr3, skb->data, ETH_ALEN);
			hdrlen = 24;

			
		}
		break;
#ifdef CONFIG_ATBM_SUPPORT_IBSS
	case NL80211_IFTYPE_ADHOC:
		/* DA SA BSSID */
		memcpy(hdr.addr1, skb->data, ETH_ALEN);
		memcpy(hdr.addr2, skb->data + ETH_ALEN, ETH_ALEN);
		memcpy(hdr.addr3, sdata->u.ibss.bssid, ETH_ALEN);
		hdrlen = 24;
		break;
#endif
	default:
		ret = NETDEV_TX_OK;
		goto fail;
	}

	/*
	 * There's no need to try to look up the destination
	 * if it is a multicast address (which can only happen
	 * in AP mode)
	 */
	if (!is_multicast_ether_addr(hdr.addr1)) {
		rcu_read_lock();
		sta = sta_info_get(sdata, hdr.addr1);
		if (sta) {
			authorized = test_sta_flag(sta, WLAN_STA_AUTHORIZED);
			wme_sta = test_sta_flag(sta, WLAN_STA_WME);
		}
		rcu_read_unlock();
	}
#ifdef CONFIG_MAC80211_ATBM_MESH
	/* For mesh, the use of the QoS header is mandatory */
	if (ieee80211_vif_is_mesh(&sdata->vif))
		wme_sta = true;
#endif

	/* receiver and we are QoS enabled, use a QoS type frame */
	if ((wme_sta && local->hw.queues >= IEEE80211_NUM_ACS)
		&&(ethertype != ETH_P_PAE)){
		fc |= cpu_to_le16(IEEE80211_STYPE_QOS_DATA);
		hdrlen += 2;
	}

	/*
	 * Drop unicast frames to unauthorised stations unless they are
	 * EAPOL frames from the local station.
	 */
	if (unlikely(!ieee80211_vif_is_mesh(&sdata->vif) &&
		     !is_multicast_ether_addr(hdr.addr1) && !authorized &&
		     (cpu_to_be16(ethertype) != sdata->control_port_protocol ||
		      atbm_compare_ether_addr(sdata->vif.addr, skb->data + ETH_ALEN)))) {
#ifdef CONFIG_MAC80211_ATBM_VERBOSE_DEBUG
		if (net_ratelimit())
			atbm_printk_debug("%s: dropped frame to %pM"
			       " (unauthorized port)\n", dev->name,
			       hdr.addr1);
#endif

		I802_DEBUG_INC(local->tx_handlers_drop_unauth_port);

		ret = NETDEV_TX_OK;
		goto fail;
	}

	/*
	 * If the skb is shared we need to obtain our own copy.
	 */
	if (skb_shared(skb)) {
		tmp_skb = skb;
		skb = skb_clone(skb, GFP_ATOMIC);
		kfree_skb(tmp_skb);

		if (!skb) {
			ret = NETDEV_TX_OK;
			goto fail;
		}
	}

	hdr.frame_control = fc;
	hdr.duration_id = 0;
	hdr.seq_ctrl = 0;

	skip_header_bytes = ETH_HLEN;
	if (ethertype == ETH_P_AARP || ethertype == ETH_P_IPX) {
		encaps_data = bridge_tunnel_header;
		encaps_len = sizeof(bridge_tunnel_header);
		skip_header_bytes -= 2;
	} else if (ethertype >= 0x600) {
		encaps_data = rfc1042_header;
		encaps_len = sizeof(rfc1042_header);
		skip_header_bytes -= 2;
	} else {
		encaps_data = NULL;
		encaps_len = 0;
	}

	nh_pos = skb_network_header(skb) - skb->data;
	h_pos = skb_transport_header(skb) - skb->data;

	atbm_skb_pull(skb, skip_header_bytes);
	nh_pos -= skip_header_bytes;
	h_pos -= skip_header_bytes;

	head_need = hdrlen + encaps_len + meshhdrlen - atbm_skb_headroom(skb);

	/*
	 * So we need to modify the skb header and hence need a copy of
	 * that. The head_need variable above doesn't, so far, include
	 * the needed header space that we don't need right away. If we
	 * can, then we don't reallocate right now but only after the
	 * frame arrives at the master device (if it does...)
	 *
	 * If we cannot, however, then we will reallocate to include all
	 * the ever needed space. Also, if we need to reallocate it anyway,
	 * make it big enough for everything we may ever need.
	 */

	if (head_need > 0 || atbm_skb_cloned(skb)) {
		head_need += IEEE80211_ENCRYPT_HEADROOM;
		head_need += local->tx_headroom;
		head_need = max_t(int, 0, head_need);
		if (ieee80211_skb_resize(sdata, skb, head_need, true))
			goto fail;
	}
	if (encaps_data) {
		memcpy(atbm_skb_push(skb, encaps_len), encaps_data, encaps_len);
		nh_pos += encaps_len;
		h_pos += encaps_len;
	}

#ifdef CONFIG_MAC80211_ATBM_MESH
	if (meshhdrlen > 0) {
		memcpy(atbm_skb_push(skb, meshhdrlen), &mesh_hdr, meshhdrlen);
		nh_pos += meshhdrlen;
		h_pos += meshhdrlen;
	}
#endif

	if (ieee80211_is_data_qos(fc)) {
		__le16 *qos_control;

		qos_control = (__le16*) atbm_skb_push(skb, 2);
		memcpy(atbm_skb_push(skb, hdrlen - 2), &hdr, hdrlen - 2);
		/*
		 * Maybe we could actually set some fields here, for now just
		 * initialise to zero to indicate no special operation.
		 */
		*qos_control = 0;
	} else
		memcpy(atbm_skb_push(skb, hdrlen), &hdr, hdrlen);

	nh_pos += hdrlen;
	h_pos += hdrlen;

	dev->stats.tx_packets++;
	dev->stats.tx_bytes += skb->len;

	/* Update skb pointers to various headers since this modified frame
	 * is going to go through Linux networking code that may potentially
	 * need things like pointer to IP header. */
	atbm_skb_set_mac_header(skb, 0);
	atbm_skb_set_network_header(skb, nh_pos);
	atbm_skb_set_transport_header(skb, h_pos);

	info = IEEE80211_SKB_CB(skb);
	memset(info, 0, sizeof(*info));
	#if (LINUX_VERSION_CODE < KERNEL_VERSION(4, 7, 0))
	dev->trans_start = jiffies;
	#endif
	ieee80211_xmit(sdata, skb);

	return NETDEV_TX_OK;

 fail:
	if (ret == NETDEV_TX_OK)
		dev_kfree_skb(skb);

	return ret;
}


/*
 * ieee80211_clear_tx_pending may not be called in a context where
 * it is possible that it packets could come in again.
 */
void ieee80211_clear_tx_pending(struct ieee80211_local *local)
{
	int i;

	for (i = 0; i < local->hw.queues; i++)
		atbm_skb_queue_purge(&local->pending[i]);
}

/*
 * Returns false if the frame couldn't be transmitted but was queued instead,
 * which in this case means re-queued -- take as an indication to stop sending
 * more pending frames.
 */
static bool ieee80211_tx_pending_skb(struct ieee80211_local *local,
				     struct sk_buff *skb)
{
	struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);
	struct ieee80211_sub_if_data *sdata;
	struct sta_info *sta;
	struct ieee80211_hdr *hdr;
	bool result;

	sdata = vif_to_sdata(info->control.vif);

	if (info->flags & IEEE80211_TX_INTFL_NEED_TXPROCESSING) {
		result = ieee80211_tx(sdata, skb, true);
	} else {
		hdr = (struct ieee80211_hdr *)skb->data;
		sta = sta_info_get(sdata, hdr->addr1);

		result = __ieee80211_tx(local, &skb, sta, true);
	}

	return result;
}

/*
 * Transmit all pending packets. Called from tasklet.
 */
void ieee80211_tx_pending(unsigned long data)
{
	struct ieee80211_local *local = (struct ieee80211_local *)data;
	unsigned long flags;
	int i;
	bool txok;

	rcu_read_lock();

	spin_lock_irqsave(&local->queue_stop_reason_lock, flags);
	for (i = 0; i < local->hw.queues; i++) {
		/*
		 * If queue is stopped by something other than due to pending
		 * frames, or we have no pending frames, proceed to next queue.
		 */
		if (local->queue_stop_reasons[i] ||
		    atbm_skb_queue_empty(&local->pending[i]))
			continue;

		while (!atbm_skb_queue_empty(&local->pending[i])) {
			struct sk_buff *skb = __atbm_skb_dequeue(&local->pending[i]);
			struct ieee80211_tx_info *info = IEEE80211_SKB_CB(skb);

			if (WARN_ON(!info->control.vif)) {
				atbm_kfree_skb(skb);
				continue;
			}

			spin_unlock_irqrestore(&local->queue_stop_reason_lock,
						flags);

			txok = ieee80211_tx_pending_skb(local, skb);
			spin_lock_irqsave(&local->queue_stop_reason_lock,
					  flags);
			if (!txok)
				break;
		}

		if (atbm_skb_queue_empty(&local->pending[i]))
			ieee80211_propagate_queue_wake(local, i);
	}
	spin_unlock_irqrestore(&local->queue_stop_reason_lock, flags);

	rcu_read_unlock();
}

/* functions for drivers to get certain frames */

static void ieee80211_beacon_add_tim(struct ieee80211_if_ap *bss,
				     struct sk_buff *skb,
				     struct beacon_data *beacon)
{
	u8 *pos, *tim;
	int aid0 = 0;
	int i, have_bits = 0, n1, n2;

	/* Generate bitmap for TIM only if there are any STAs in power save
	 * mode. */
	if (atomic_read(&bss->num_sta_ps) > 0)
		/* in the hope that this is faster than
		 * checking byte-for-byte */
		have_bits = !bitmap_empty((unsigned long*)bss->tim,
					  IEEE80211_MAX_AID+1);

	if (bss->dtim_count == 0)
		bss->dtim_count = beacon->dtim_period - 1;
	else
		bss->dtim_count--;

	tim = pos = (u8 *) atbm_skb_put(skb, 6);
	*pos++ = ATBM_WLAN_EID_TIM;
	*pos++ = 4;
	*pos++ = bss->dtim_count;
	*pos++ = beacon->dtim_period;

	if (bss->dtim_count == 0 && !atbm_skb_queue_empty(&bss->ps_bc_buf))
		aid0 = 1;

	bss->dtim_bc_mc = aid0 == 1;

	if (have_bits) {
		/* Find largest even number N1 so that bits numbered 1 through
		 * (N1 x 8) - 1 in the bitmap are 0 and number N2 so that bits
		 * (N2 + 1) x 8 through 2007 are 0. */
		n1 = 0;
		for (i = 0; i < IEEE80211_MAX_TIM_LEN; i++) {
			if (bss->tim[i]) {
				n1 = i & 0xfe;
				break;
			}
		}
		n2 = n1;
		for (i = IEEE80211_MAX_TIM_LEN - 1; i >= n1; i--) {
			if (bss->tim[i]) {
				n2 = i;
				break;
			}
		}

		/* Bitmap control */
		*pos++ = n1 | aid0;
		/* Part Virt Bitmap */
		memcpy(pos, bss->tim + n1, n2 - n1 + 1);

		tim[1] = n2 - n1 + 4;
		atbm_skb_put(skb, n2 - n1);
	} else {
		*pos++ = aid0; /* Bitmap control */
		*pos++ = 0; /* Part Virt Bitmap */
	}
}

struct sk_buff *ieee80211_beacon_get_tim(struct ieee80211_hw *hw,
					 struct ieee80211_vif *vif,
					 u16 *tim_offset, u16 *tim_length)
{
	struct ieee80211_local *local = hw_to_local(hw);
	struct ieee80211_channel_state *chan_state;
	struct sk_buff *skb = NULL;
	struct ieee80211_tx_info *info;
	struct ieee80211_sub_if_data *sdata = NULL;
	struct ieee80211_if_ap *ap = NULL;
	struct beacon_data *beacon;
#ifndef CONFIG_RATE_HW_CONTROL
	struct ieee80211_supported_band *sband;
#endif
	enum ieee80211_band band;
#ifndef CONFIG_RATE_HW_CONTROL
	struct ieee80211_tx_rate_control txrc;
#endif
	rcu_read_lock();

	sdata = vif_to_sdata(vif);
	chan_state = ieee80211_get_channel_state(local, sdata);
	band = chan_state->conf.channel->band;
#ifndef CONFIG_RATE_HW_CONTROL
	sband = local->hw.wiphy->bands[band];
#endif

	if (!ieee80211_sdata_running(sdata))
		goto out;

	if (tim_offset)
		*tim_offset = 0;
	if (tim_length)
		*tim_length = 0;

	if (sdata->vif.type == NL80211_IFTYPE_AP) {
		struct beacon_extra *extra;
		
		ap = &sdata->u.ap;
		extra = rcu_dereference(ap->beacon_extra);
		beacon = rcu_dereference(ap->beacon);
		if (beacon) {
			int beacon_size;

			beacon_size = local->tx_headroom+beacon->head_len +
					    beacon->tail_len + 256;
			if(extra)
				beacon_size += extra->beacon_extra_len;
			/*
			 * headroom, head length,
			 * tail length and maximum TIM length
			 */
			skb = atbm_dev_alloc_skb(beacon_size);
			if (!skb)
				goto out;

			atbm_skb_reserve(skb, local->tx_headroom);
			memcpy(atbm_skb_put(skb, beacon->head_len), beacon->head,
			       beacon->head_len);

			/*
			 * Not very nice, but we want to allow the driver to call
			 * ieee80211_beacon_get() as a response to the set_tim()
			 * callback. That, however, is already invoked under the
			 * sta_lock to guarantee consistent and race-free update
			 * of the tim bitmap in mac80211 and the driver.
			 */
			if (local->tim_in_locked_section) {
				ieee80211_beacon_add_tim(ap, skb, beacon);
			} else {
				unsigned long flags;

				spin_lock_irqsave(&local->sta_lock, flags);
				ieee80211_beacon_add_tim(ap, skb, beacon);
				spin_unlock_irqrestore(&local->sta_lock, flags);
			}

			if (tim_offset)
				*tim_offset = beacon->head_len;
			if (tim_length)
				*tim_length = skb->len - beacon->head_len;

			if (beacon->tail)
				memcpy(atbm_skb_put(skb, beacon->tail_len),
				       beacon->tail, beacon->tail_len);
			if(extra&&extra->beacon_extra_len){
				memcpy(atbm_skb_put(skb, extra->beacon_extra_len),
				       extra->beacon_extra_ie, extra->beacon_extra_len);
			}
		} else
			goto out;
	} 
#ifdef CONFIG_ATBM_SUPPORT_IBSS
	else if (sdata->vif.type == NL80211_IFTYPE_ADHOC) {
		struct ieee80211_if_ibss *ifibss = &sdata->u.ibss;
		struct ieee80211_hdr *hdr;
		struct sk_buff *presp = rcu_dereference(ifibss->presp);

		if (!presp)
			goto out;

		skb = atbm_skb_copy(presp, GFP_ATOMIC);
		if (!skb)
			goto out;

		hdr = (struct ieee80211_hdr *) skb->data;
		hdr->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
						 IEEE80211_STYPE_BEACON);
	} 
#endif
#ifdef	CONFIG_MAC80211_ATBM_MESH
	else if (ieee80211_vif_is_mesh(&sdata->vif)) {
		struct atbm_ieee80211_mgmt *mgmt;
		u8 *pos;

#ifdef CONFIG_MAC80211_ATBM_MESH
		if (!sdata->u.mesh.mesh_id_len)
			goto out;
#endif

		/* headroom, head length, tail length and maximum TIM length */
		skb = atbm_dev_alloc_skb(local->tx_headroom + 400 +
				sdata->u.mesh.ie_len);
		if (!skb)
			goto out;

		atbm_skb_reserve(skb, local->hw.extra_tx_headroom);
		mgmt = (struct atbm_ieee80211_mgmt *)
			atbm_skb_put(skb, 24 + sizeof(mgmt->u.beacon));
		memset(mgmt, 0, 24 + sizeof(mgmt->u.beacon));
		mgmt->frame_control =
		    cpu_to_le16(IEEE80211_FTYPE_MGMT | IEEE80211_STYPE_BEACON);
		memset(mgmt->da, 0xff, ETH_ALEN);
		memcpy(mgmt->sa, sdata->vif.addr, ETH_ALEN);
		memcpy(mgmt->bssid, sdata->vif.addr, ETH_ALEN);
		mgmt->u.beacon.beacon_int =
			cpu_to_le16(sdata->vif.bss_conf.beacon_int);
		mgmt->u.beacon.capab_info |= cpu_to_le16(
			sdata->u.mesh.security ? WLAN_CAPABILITY_PRIVACY : 0);

		pos = atbm_skb_put(skb, 2);
		*pos++ = ATBM_WLAN_EID_SSID;
		*pos++ = 0x0;

		if (ieee80211_add_srates_ie(&sdata->vif, skb) ||
		    mesh_add_ds_params_ie(skb, sdata) ||
		    ieee80211_add_ext_srates_ie(&sdata->vif, skb) ||
		    mesh_add_rsn_ie(skb, sdata) ||
		    mesh_add_meshid_ie(skb, sdata) ||
		    mesh_add_meshconf_ie(skb, sdata) ||
		    mesh_add_vendor_ies(skb, sdata)) {
			pr_err("o11s: couldn't add ies!\n");
			goto out;
		}
	}
#endif
	else {
		WARN_ON(1);
		goto out;
	}

	info = IEEE80211_SKB_CB(skb);

	info->flags |= IEEE80211_TX_INTFL_DONT_ENCRYPT;
	info->flags |= IEEE80211_TX_CTL_NO_ACK;
	info->band = band;
#ifndef CONFIG_RATE_HW_CONTROL
	memset(&txrc, 0, sizeof(txrc));
	txrc.hw = hw;
	txrc.sband = sband;
	txrc.bss_conf = &sdata->vif.bss_conf;
	txrc.skb = skb;
	txrc.reported_rate.idx = -1;
	txrc.rate_idx_mask = sdata->rc_rateidx_mask[band];
	if (txrc.rate_idx_mask == (1 << sband->n_bitrates) - 1)
		txrc.max_rate_idx = -1;
	else
		txrc.max_rate_idx = fls(txrc.rate_idx_mask) - 1;
	txrc.bss = true;
	rate_control_get_rate(sdata, NULL, &txrc);
#endif
	info->control.vif = vif;

	info->flags |= IEEE80211_TX_CTL_CLEAR_PS_FILT |
			IEEE80211_TX_CTL_ASSIGN_SEQ |
			IEEE80211_TX_CTL_FIRST_FRAGMENT;
 out:
	rcu_read_unlock();
	return skb;
}
//EXPORT_SYMBOL(ieee80211_beacon_get_tim);

#ifdef ATBM_PROBE_RESP_EXTRA_IE
struct sk_buff *ieee80211_proberesp_get(struct ieee80211_hw *hw,
						   struct ieee80211_vif *vif)
{
	struct ieee80211_local *local = hw_to_local(hw);
	struct sk_buff *skb = NULL;
	struct ieee80211_channel_state *chan_state;
	struct ieee80211_tx_info *info;
	struct ieee80211_sub_if_data *sdata = NULL;
	struct ieee80211_if_ap *ap = NULL;
	struct proberesp_data *proberesp;
#ifndef CONFIG_RATE_HW_CONTROL
	struct ieee80211_supported_band *sband;
#endif
	enum ieee80211_band band;
#ifndef CONFIG_RATE_HW_CONTROL
	struct ieee80211_tx_rate_control txrc;
#endif

	rcu_read_lock();

	sdata = vif_to_sdata(vif);
	chan_state = ieee80211_get_channel_state(local, sdata);
	band = chan_state->conf.channel->band;
#ifndef CONFIG_RATE_HW_CONTROL
	sband = local->hw.wiphy->bands[band];
#endif

	if (!ieee80211_sdata_running(sdata))
		goto out;

	if (sdata->vif.type == NL80211_IFTYPE_AP) {
		struct probe_response_extra *extra;
		ap = &sdata->u.ap;
		extra     = rcu_dereference(ap->probe_response_extra);
		proberesp = rcu_dereference(ap->proberesp);
		if (proberesp) {
			int proberesp_size;

			proberesp_size = local->tx_headroom +
					    proberesp->head_len + proberesp->proberesp_data_ies_len +
					    proberesp->tail_len;
			if(extra)
				proberesp_size += extra->probe_response_extra_len;
			/*
			 * headroom, head length,
			 * tail length and probe response ie length
			 */
			skb = atbm_dev_alloc_skb(proberesp_size);
			if (!skb)
				goto out;

			atbm_skb_reserve(skb, local->tx_headroom);
			memcpy(atbm_skb_put(skb, proberesp->head_len), proberesp->head,
			       proberesp->head_len);

			if (proberesp->tail)
				memcpy(atbm_skb_put(skb, proberesp->tail_len),
				       proberesp->tail, proberesp->tail_len);

			if (proberesp->proberesp_data_ies)
				memcpy(atbm_skb_put(skb, proberesp->proberesp_data_ies_len),
				       proberesp->proberesp_data_ies, proberesp->proberesp_data_ies_len);
			if(extra&&extra->probe_response_extra_ie)
				memcpy(atbm_skb_put(skb, extra->probe_response_extra_len),
				       extra->probe_response_extra_ie, extra->probe_response_extra_len);
		} else
			goto out;
	}
	else if (sdata->vif.type == NL80211_IFTYPE_ADHOC) {
		goto out;
	}
	else {
		
		WARN_ON(1);
		goto out;
	}

	info = IEEE80211_SKB_CB(skb);

	info->flags |= IEEE80211_TX_INTFL_DONT_ENCRYPT;
	//info->flags |= IEEE80211_TX_CTL_NO_ACK;
	info->band = band;
#ifndef CONFIG_RATE_HW_CONTROL
	memset(&txrc, 0, sizeof(txrc));
	txrc.hw = hw;
	txrc.sband = sband;
	txrc.bss_conf = &sdata->vif.bss_conf;
	txrc.skb = skb;
	txrc.reported_rate.idx = -1;
	txrc.rate_idx_mask = sdata->rc_rateidx_mask[band];
	if (txrc.rate_idx_mask == (1 << sband->n_bitrates) - 1)
		txrc.max_rate_idx = -1;
	else
		txrc.max_rate_idx = fls(txrc.rate_idx_mask) - 1;
	txrc.bss = true;
	rate_control_get_rate(sdata, NULL, &txrc);
#endif

	info->control.vif = vif;

	info->flags |= IEEE80211_TX_CTL_CLEAR_PS_FILT |
			IEEE80211_TX_CTL_ASSIGN_SEQ |
			IEEE80211_TX_CTL_FIRST_FRAGMENT;
 out:
	rcu_read_unlock();
	return skb;
}
//EXPORT_SYMBOL(ieee80211_proberesp_get);
#endif
#if defined (CONFIG_ATBM_MAC80211_NO_USE) || defined (CONFIG_ATBM_BT_COMB)
struct sk_buff *ieee80211_pspoll_get(struct ieee80211_hw *hw,
				     struct ieee80211_vif *vif)
{
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_if_managed *ifmgd;
	struct ieee80211_pspoll *pspoll;
	struct ieee80211_local *local;
	struct sk_buff *skb;

	if (WARN_ON(vif->type != NL80211_IFTYPE_STATION))
		return NULL;

	sdata = vif_to_sdata(vif);
	ifmgd = &sdata->u.mgd;
	local = sdata->local;

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom + sizeof(*pspoll));
	if (!skb)
		return NULL;

	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	pspoll = (struct ieee80211_pspoll *) atbm_skb_put(skb, sizeof(*pspoll));
	memset(pspoll, 0, sizeof(*pspoll));
	pspoll->frame_control = cpu_to_le16(IEEE80211_FTYPE_CTL |
					    IEEE80211_STYPE_PSPOLL);
	pspoll->aid = cpu_to_le16(ifmgd->aid);

	/* aid in PS-Poll has its two MSBs each set to 1 */
	pspoll->aid |= cpu_to_le16(1 << 15 | 1 << 14);

	memcpy(pspoll->bssid, ifmgd->bssid, ETH_ALEN);
	memcpy(pspoll->ta, vif->addr, ETH_ALEN);

	return skb;
}
//EXPORT_SYMBOL(ieee80211_pspoll_get);
struct sk_buff *ieee80211_nullfunc_get(struct ieee80211_hw *hw,
				       struct ieee80211_vif *vif)
{
	struct ieee80211_hdr_3addr *nullfunc;
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_if_managed *ifmgd;
	struct ieee80211_local *local;
	struct sk_buff *skb;

	if (WARN_ON(vif->type != NL80211_IFTYPE_STATION))
		return NULL;

	sdata = vif_to_sdata(vif);
	ifmgd = &sdata->u.mgd;
	local = sdata->local;

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom + sizeof(*nullfunc));
	if (!skb)
		return NULL;

	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	nullfunc = (struct ieee80211_hdr_3addr *) atbm_skb_put(skb,
							  sizeof(*nullfunc));
	memset(nullfunc, 0, sizeof(*nullfunc));
	nullfunc->frame_control = cpu_to_le16(IEEE80211_FTYPE_DATA |
					      IEEE80211_STYPE_NULLFUNC |
					      IEEE80211_FCTL_TODS);
	memcpy(nullfunc->addr1, ifmgd->bssid, ETH_ALEN);
	memcpy(nullfunc->addr2, vif->addr, ETH_ALEN);
	memcpy(nullfunc->addr3, ifmgd->bssid, ETH_ALEN);

	return skb;
}
//EXPORT_SYMBOL(ieee80211_nullfunc_get);
#endif

struct sk_buff *ieee80211_qosnullfunc_get(struct ieee80211_hw *hw,
					  struct ieee80211_vif *vif)
{
	struct ieee80211_qos_hdr *nullfunc;
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_if_managed *ifmgd;
	struct ieee80211_local *local;
	struct sk_buff *skb;

	if (WARN_ON(vif->type != NL80211_IFTYPE_STATION))
		return NULL;

	sdata = vif_to_sdata(vif);
	ifmgd = &sdata->u.mgd;
	local = sdata->local;

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom + sizeof(*nullfunc));
	if (!skb) {
		atbm_printk_err( "%s: failed to allocate buffer for qos "
		       "nullfunc template\n", sdata->name);
		return NULL;
	}
	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	nullfunc = (struct ieee80211_qos_hdr *) atbm_skb_put(skb,
							  sizeof(*nullfunc));
	memset(nullfunc, 0, sizeof(*nullfunc));
	nullfunc->frame_control = cpu_to_le16(IEEE80211_FTYPE_DATA |
					      IEEE80211_STYPE_QOS_NULLFUNC |
					      IEEE80211_FCTL_TODS);
	memcpy(nullfunc->addr1, ifmgd->bssid, ETH_ALEN);
	memcpy(nullfunc->addr2, vif->addr, ETH_ALEN);
	memcpy(nullfunc->addr3, ifmgd->bssid, ETH_ALEN);

	return skb;
}
//EXPORT_SYMBOL(ieee80211_qosnullfunc_get);

struct sk_buff *ieee80211_probereq_get(struct ieee80211_hw *hw,
				       struct ieee80211_vif *vif,
				       const u8 *ssid, size_t ssid_len,
				       const u8 *ie, size_t ie_len)
{
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_local *local;
	struct ieee80211_hdr_3addr *hdr;
	struct sk_buff *skb;
	size_t ie_ssid_len;
	u8 *pos;
	struct probe_request_extra *extra = NULL;
	size_t extra_len = 0;
	
	rcu_read_lock();
	
	sdata = vif_to_sdata(vif);
	local = sdata->local;
	ie_ssid_len = 2 + ssid_len;
	/*
	*if vif is in station mode try to add extra ie;
	*/
	if(ieee80211_sdata_running(sdata) && (vif->type == NL80211_IFTYPE_STATION)){
		extra = rcu_dereference(sdata->u.mgd.probe_request_extra);
	}
	
	if(extra)
		extra_len = extra->probe_request_extra_len;
	
	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom + sizeof(*hdr) +
			    ie_ssid_len + ie_len + extra_len);
	if (!skb){
		goto out;
	}

	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	hdr = (struct ieee80211_hdr_3addr *) atbm_skb_put(skb, sizeof(*hdr));
	memset(hdr, 0, sizeof(*hdr));
	hdr->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					 IEEE80211_STYPE_PROBE_REQ);
	memset(hdr->addr1, 0xff, ETH_ALEN);
	memcpy(hdr->addr2, vif->addr, ETH_ALEN);
	memset(hdr->addr3, 0xff, ETH_ALEN);
	pos = atbm_skb_put(skb, ie_ssid_len);
	*pos++ = ATBM_WLAN_EID_SSID;
	*pos++ = ssid_len;
	if (ssid)
		memcpy(pos, ssid, ssid_len);
	pos += ssid_len;

	if (ie) {
		pos = atbm_skb_put(skb, ie_len);
		memcpy(pos, ie, ie_len);
	}

	if(extra){
		pos = atbm_skb_put(skb, extra_len);
		memcpy(pos,extra->probe_request_extra_ie,extra_len);
	}
out:
	rcu_read_unlock();
	return skb;
}
//EXPORT_SYMBOL(ieee80211_probereq_get);

//EXPORT_SYMBOL(ieee80211_qosnullfunc_get);


struct sk_buff *ieee80211_probereq_get_etf(struct ieee80211_hw *hw,
				       struct ieee80211_vif *vif,
				       const u8 *ssid, size_t ssid_len,
				       size_t total_len)
{
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_local *local;
	struct ieee80211_hdr_3addr *hdr;
	struct sk_buff *skb;
	size_t ie_ssid_len;
	int data_len;

	u8 *pos;

	data_len = total_len - sizeof(*hdr) -ssid_len;

	sdata = vif_to_sdata(vif);
	local = sdata->local;
	ie_ssid_len = 2 + ssid_len;

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom + sizeof(*hdr) +
			    ie_ssid_len + data_len+8);
	if (!skb)
		return NULL;

	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	hdr = (struct ieee80211_hdr_3addr *) atbm_skb_put(skb, sizeof(*hdr));
	memset(hdr, 0, sizeof(*hdr));
	hdr->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					 IEEE80211_STYPE_PROBE_REQ);
	memset(hdr->addr1, 0xff, ETH_ALEN);
	memcpy(hdr->addr2, vif->addr, ETH_ALEN);
	memset(hdr->addr3, 0xff, ETH_ALEN);
	pos = atbm_skb_put(skb, ie_ssid_len);
	*pos++ = ATBM_WLAN_EID_SSID;
	*pos++ = ssid_len;
	if (ssid)
		memcpy(pos, ssid, ssid_len);
	pos += ssid_len;

	while(1)
	{
		pos = atbm_skb_put(skb, 8);
		*pos++ = 221;
		*pos++ = 6;
		pos += 6;
		data_len -=8;
		if(data_len<0)
			break;
	}

	return skb;
}


struct sk_buff *ieee80211_probereq_get_etf_v2(struct ieee80211_hw *hw,
				       struct ieee80211_vif *vif,
				       const u8 *ssid, size_t ssid_len,
				       size_t total_len)
{
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_local *local;
	struct ieee80211_hdr_3addr *hdr;
	struct sk_buff *skb;
	size_t ie_ssid_len;
	int data_len;	
	struct ATBM_TEST_IE  *pAtbm_Ie;
			u8 out[3]=ATBM_OUI;

	u8 *pos;

	data_len =12*sizeof(struct ATBM_TEST_IE) ;

	sdata = vif_to_sdata(vif);
	local = sdata->local;
	ie_ssid_len = 2 + ssid_len;

	skb = atbm_dev_alloc_skb(2*(local->hw.extra_tx_headroom + sizeof(*hdr) +
			    ie_ssid_len + data_len));

	
	if (!skb)
		return NULL;
	
	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	hdr = (struct ieee80211_hdr_3addr *) atbm_skb_put(skb, sizeof(*hdr));
	memset(hdr, 0, sizeof(*hdr));
	hdr->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					 IEEE80211_STYPE_PROBE_REQ);
	memset(hdr->addr1, 0xff, ETH_ALEN);
	memcpy(hdr->addr2, vif->addr, ETH_ALEN);
	memset(hdr->addr3, 0xff, ETH_ALEN);
	pos = atbm_skb_put(skb, ie_ssid_len);
	*pos++ = ATBM_WLAN_EID_SSID;
	*pos++ = ssid_len;
	if (ssid)
		memcpy(pos, ssid, ssid_len);
	pos += ssid_len;

	*pos++ = ATBM_WLAN_EID_SUPP_RATES;
	*pos++ = 7;//len
	*pos++ = 2;	
	*pos++ = 4;	
	*pos++ = 11;	
	*pos++ = 22;	
	*pos++ = 12;	
	*pos++ = 24;	
	*pos++ = 48;

	*pos++ = ATBM_WLAN_EID_EXT_SUPP_RATES;
	*pos++ = 5;//len
	*pos++ = 18;	
	*pos++ = 36;	
	*pos++ = 72;	
	*pos++ = 96;	
	*pos++ = 108;	
	

	pos = atbm_skb_put(skb, 7+5+4);


	while(1)
	{		

		pos = atbm_skb_put(skb, sizeof(struct ATBM_TEST_IE));
		//*pos++ = 221;
		//*pos++ = 6;
		pAtbm_Ie=(struct ATBM_TEST_IE  *)pos;
			
		pAtbm_Ie->ie_id = D11_WIFI_ELT_ID;
		pAtbm_Ie->len = sizeof(struct ATBM_TEST_IE)-2;
		memcpy(pAtbm_Ie->oui, out,3);
		pAtbm_Ie->oui_type = WIFI_ATBM_IE_OUI_TYPE;
		pAtbm_Ie->test_type = TXRX_TEST_REQ;
#ifdef ATBM_PRODUCT_TEST_USE_FEATURE_ID
		pAtbm_Ie->featureid = gthreshold_param.featureid;
#endif
		pAtbm_Ie->result[0] = gthreshold_param.rssifilter;
		pAtbm_Ie->result[1] = gthreshold_param.rxevm;
		pos +=sizeof(struct ATBM_TEST_IE);


		
		data_len -=sizeof(struct ATBM_TEST_IE);
		if(data_len<=0)
			break;
	}
	

	//frame_hexdump("etf probe req", hdr,skb->len);
	return skb;
}
#ifdef CONFIG_ATBM_PRODUCT_TEST_USE_GOLDEN_LED
struct sk_buff *ieee80211_probereq_get_etf_for_send_result(struct ieee80211_hw *hw,
				       struct ieee80211_vif *vif,
				       const u8 *ssid, size_t ssid_len,
				       size_t total_len)
{
	struct ieee80211_sub_if_data *sdata;
	struct ieee80211_local *local;
	struct ieee80211_hdr_3addr *hdr;
	struct sk_buff *skb;
	size_t ie_ssid_len;
	int data_len;	
	struct ATBM_TEST_IE  *pAtbm_Ie;
			u8 out[3]=ATBM_OUI;

	u8 *pos;

	data_len = 8*sizeof(struct ATBM_TEST_IE) ;

	sdata = vif_to_sdata(vif);
	local = sdata->local;
	ie_ssid_len = 2 + ssid_len;

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom + sizeof(*hdr) +
			    ie_ssid_len + data_len);

	
	if (!skb)
		return NULL;
	
	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);

	hdr = (struct ieee80211_hdr_3addr *) atbm_skb_put(skb, sizeof(*hdr));
	memset(hdr, 0, sizeof(*hdr));
	hdr->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					 IEEE80211_STYPE_PROBE_REQ);
	memset(hdr->addr1, 0xff, ETH_ALEN);
	memcpy(hdr->addr2, vif->addr, ETH_ALEN);
	memset(hdr->addr3, 0xff, ETH_ALEN);
	pos = atbm_skb_put(skb, ie_ssid_len);
	*pos++ = ATBM_WLAN_EID_SSID;
	*pos++ = ssid_len;
	if (ssid)
		memcpy(pos, ssid, ssid_len);
	pos += ssid_len;

	*pos++ = ATBM_WLAN_EID_SUPP_RATES;
	*pos++ = 7;//len
	*pos++ = 2;	
	*pos++ = 4;	
	*pos++ = 11;	
	*pos++ = 22;	
	*pos++ = 12;	
	*pos++ = 24;	
	*pos++ = 48;

	*pos++ = ATBM_WLAN_EID_EXT_SUPP_RATES;
	*pos++ = 5;//len
	*pos++ = 18;	
	*pos++ = 36;	
	*pos++ = 72;	
	*pos++ = 96;	
	*pos++ = 108;	
	

	pos = atbm_skb_put(skb, 7+5+4);


	while(1)
	{		

		pos = atbm_skb_put(skb, sizeof(struct ATBM_TEST_IE));
		//*pos++ = 221;
		//*pos++ = 6;
		pAtbm_Ie=(struct ATBM_TEST_IE  *)pos;
			
		pAtbm_Ie->ie_id = D11_WIFI_ELT_ID;
		pAtbm_Ie->len = sizeof(struct ATBM_TEST_IE)-2;
		memcpy(pAtbm_Ie->oui, out,3);
		pAtbm_Ie->oui_type = WIFI_ATBM_IE_OUI_TYPE;
		pAtbm_Ie->test_type = TXRX_TEST_RESULT;
#ifdef ATBM_PRODUCT_TEST_USE_FEATURE_ID
		pAtbm_Ie->featureid = gthreshold_param.featureid;
#endif
		if(Atbm_Test_Success == 1){
			pAtbm_Ie->resverd = TXRX_TEST_PASS;
		}
		else if(Atbm_Test_Success == -1)
		{
			pAtbm_Ie->resverd = TXRX_TEST_FAIL;
		}
		
		pos +=sizeof(struct ATBM_TEST_IE);


		
		data_len -=sizeof(struct ATBM_TEST_IE);
		if(data_len<=0)
			break;
	}

	//frame_hexdump("etf probe req", hdr,skb->len);
	return skb;
}
#endif
#ifdef CONFIG_ATBM_MAC80211_NO_USE
void ieee80211_rts_get(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
		       const void *frame, size_t frame_len,
		       const struct ieee80211_tx_info *frame_txctl,
		       struct ieee80211_rts *rts)
{
	const struct ieee80211_hdr *hdr = frame;

	rts->frame_control =
	    cpu_to_le16(IEEE80211_FTYPE_CTL | IEEE80211_STYPE_RTS);
	rts->duration = ieee80211_rts_duration(hw, vif, frame_len,
					       frame_txctl);
	memcpy(rts->ra, hdr->addr1, sizeof(rts->ra));
	memcpy(rts->ta, hdr->addr2, sizeof(rts->ta));
}
//EXPORT_SYMBOL(ieee80211_rts_get);

void ieee80211_ctstoself_get(struct ieee80211_hw *hw, struct ieee80211_vif *vif,
			     const void *frame, size_t frame_len,
			     const struct ieee80211_tx_info *frame_txctl,
			     struct ieee80211_cts *cts)
{
	const struct ieee80211_hdr *hdr = frame;

	cts->frame_control =
	    cpu_to_le16(IEEE80211_FTYPE_CTL | IEEE80211_STYPE_CTS);
	cts->duration = ieee80211_ctstoself_duration(hw, vif,
						     frame_len, frame_txctl);
	memcpy(cts->ra, hdr->addr1, sizeof(cts->ra));
}
//EXPORT_SYMBOL(ieee80211_ctstoself_get);
#endif
struct sk_buff *
ieee80211_get_buffered_bc(struct ieee80211_hw *hw,
			  struct ieee80211_vif *vif)
{
	struct ieee80211_local *local = hw_to_local(hw);
	struct ieee80211_sub_if_data *sdata = vif_to_sdata(vif);
	struct ieee80211_channel_state *chan_state = ieee80211_get_channel_state(local, sdata);
	struct sk_buff *skb = NULL;
	struct ieee80211_tx_data tx;
	struct ieee80211_if_ap *bss = NULL;
	struct beacon_data *beacon;
	struct ieee80211_tx_info *info;

	bss = &sdata->u.ap;

	rcu_read_lock();
	beacon = rcu_dereference(bss->beacon);

	if (sdata->vif.type != NL80211_IFTYPE_AP || !beacon || !beacon->head)
		goto out;

	if (bss->dtim_count != 0 || !bss->dtim_bc_mc)
		goto out; /* send buffered bc/mc only after DTIM beacon */

	while (1) {
		skb = atbm_skb_dequeue(&bss->ps_bc_buf);
		if (!skb)
			goto out;
		local->total_ps_buffered--;

		if (!atbm_skb_queue_empty(&bss->ps_bc_buf) && skb->len >= 2) {
			struct ieee80211_hdr *hdr =
				(struct ieee80211_hdr *) skb->data;
			/* more buffered multicast/broadcast frames ==> set
			 * MoreData flag in IEEE 802.11 header to inform PS
			 * STAs */
			hdr->frame_control |=
				cpu_to_le16(IEEE80211_FCTL_MOREDATA);
		}

		if (!ieee80211_tx_prepare(sdata, &tx, skb))
			break;
		atbm_dev_kfree_skb_any(skb);
	}

	info = IEEE80211_SKB_CB(skb);

	tx.flags |= IEEE80211_TX_PS_BUFFERED;
	tx.channel = chan_state->conf.channel;
	info->band = tx.channel->band;

	if (invoke_tx_handlers(&tx))
		skb = NULL;
 out:
	rcu_read_unlock();

	return skb;
}
//EXPORT_SYMBOL(ieee80211_get_buffered_bc);

void ieee80211_tx_skb(struct ieee80211_sub_if_data *sdata, struct sk_buff *skb)
{
	atbm_skb_set_mac_header(skb, 0);
	atbm_skb_set_network_header(skb, 0);
	atbm_skb_set_transport_header(skb, 0);

	/* Send all internal mgmt frames on VO. Accordingly set TID to 7. */
	atbm_skb_set_queue_mapping(skb, IEEE80211_AC_VO);
	skb->priority = 7;

	/*
	 * The other path calling ieee80211_xmit is from the tasklet,
	 * and while we can handle concurrent transmissions locking
	 * requirements are that we do not come into tx with bhs on.
	 */
	local_bh_disable();
	ieee80211_xmit(sdata, skb);
	local_bh_enable();
}

bool ieee80211_tx_multicast_deauthen(struct ieee80211_sub_if_data *sdata)
{
	struct sk_buff *skb;
	struct atbm_ieee80211_mgmt *mgmt;
	struct ieee80211_local *local = sdata->local;
	u8 multicast_addr[ETH_ALEN] = {0xff,0xff,0xff,0xff,0xff,0xff};
	
	if(sdata->vif.type != NL80211_IFTYPE_AP){
		return false;
	}

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom +sizeof(*mgmt) + 6);
	if (!skb){
		return false;
	}

	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);
	atbm_printk_mgmt( "%s:[%pM] send deauthen\n",sdata->name,sdata->vif.addr);
	mgmt = (struct atbm_ieee80211_mgmt *) atbm_skb_put(skb, sizeof(struct atbm_ieee80211_mgmt));
	memset(mgmt, 0, 24 + 6);
	mgmt->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					  IEEE80211_STYPE_DEAUTH|IEEE80211_FCTL_FROMDS);
	memcpy(mgmt->da, multicast_addr, ETH_ALEN);
	memcpy(mgmt->sa, sdata->vif.addr, ETH_ALEN);
	memcpy(mgmt->bssid, sdata->vif.addr, ETH_ALEN);
	mgmt->u.deauth.reason_code = WLAN_REASON_DEAUTH_LEAVING;

	IEEE80211_SKB_CB(skb)->flags = IEEE80211_TX_INTFL_DONT_ENCRYPT | IEEE80211_TX_CTL_USE_MINRATE;

	ieee80211_tx_skb(sdata,skb);

	return true;
}

bool ieee80211_tx_sta_deauthen(struct sta_info *sta)
{
	struct sk_buff *skb;
	struct atbm_ieee80211_mgmt *mgmt;
	struct ieee80211_sub_if_data *sdata = sta->sdata;
	struct ieee80211_local *local = sdata->local;
	
	if(sdata->vif.type != NL80211_IFTYPE_AP){
		return false;
	}

	skb = atbm_dev_alloc_skb(local->hw.extra_tx_headroom +sizeof(*mgmt) + 6);
	if (!skb){
		return false;
	}

	atbm_skb_reserve(skb, local->hw.extra_tx_headroom);
	atbm_printk_mgmt( "%s:[%pM] send deauthen\n",sdata->name,sta->sta.addr);
	mgmt = (struct atbm_ieee80211_mgmt *) atbm_skb_put(skb, sizeof(struct atbm_ieee80211_mgmt));
	memset(mgmt, 0, 24 + 6);
	mgmt->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					  IEEE80211_STYPE_DEAUTH|IEEE80211_FCTL_FROMDS);
	memcpy(mgmt->da, sta->sta.addr, ETH_ALEN);
	memcpy(mgmt->sa, sdata->vif.addr, ETH_ALEN);
	memcpy(mgmt->bssid, sdata->vif.addr, ETH_ALEN);
	mgmt->u.deauth.reason_code = WLAN_REASON_DEAUTH_LEAVING;

	IEEE80211_SKB_CB(skb)->flags = IEEE80211_TX_INTFL_DONT_ENCRYPT | IEEE80211_TX_CTL_USE_MINRATE;

	ieee80211_tx_skb(sdata,skb);

	return true;
}


