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
#ifdef LINUX_OS
#include <linux/version.h>
#include <linux/module.h>
#include <linux/kernel.h>
#include <net/atbm_mac80211.h>
#include <linux/etherdevice.h>
#include <linux/skbuff.h>
#include <linux/udp.h>
#include <net/ip.h>
#include <linux/bitops.h>
#endif
#include "apollo.h"
#include "wsm.h"
#include "bh.h"
#include "hwio.h"
#include "sbus.h"
#include "ieee80211_i.h"


#if defined(CONFIG_ATBM_APOLLO_TX_POLICY_DEBUG)
#define tx_policy_printk(...) atbm_printk_always(__VA_ARGS__)
#else
#define tx_policy_printk(...)
#endif
/* ******************************************************************** */
static int atbm_submit_package(struct atbm_common *hw_priv,struct sk_buff *skb)
{
	atbm_skb_queue_tail(&hw_priv->tx_frame_queue, skb);
	#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	spin_lock_irqsave(&hw_priv->tx_queue_lock, 0);
	#else
	spin_lock_bh(&hw_priv->tx_queue_lock);
	#endif
	hw_priv->tx_num_queued++;
	if (hw_priv->tx_queue_overfull == false && hw_priv->tx_num_queued >= ATBM_WIFI_MAX_QUEUE_SZ){
		hw_priv->tx_queue_overfull = true;
		#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
		spin_unlock_irqrestore(&hw_priv->tx_queue_lock, 0);
		#else
		spin_unlock_bh(&hw_priv->tx_queue_lock);
		#endif
		netif_tx_stop_all_queues(hw_priv->vif_list[0]->ndev);
		#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
		spin_lock_irqsave(&hw_priv->tx_queue_lock, 0);
		#else
		spin_lock_bh(&hw_priv->tx_queue_lock);
		#endif
	}
	#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	spin_unlock_irqrestore(&hw_priv->tx_queue_lock, 0);
	#else
	spin_unlock_bh(&hw_priv->tx_queue_lock);
	#endif
	atbm_bh_wakeup(hw_priv);
	return 0;
}
static int atbm_tx_h_crypt(struct sta_info *sta,
		 struct sk_buff *skb,struct atbm_vif *vif)
{
	struct ieee80211_hdr *hdr;
	u8 *newhdr;
	enum ieee80211_enc_type enc_type; 
	u8 iv_len;
	
	if(sta == NULL){
		enc_type = vif->group_key.key_type;
		iv_len  = vif->group_key.conf.iv_len;
	}else {
		enc_type = sta->key.key_type;
		iv_len  = sta->key.conf.iv_len;
	}
	if(enc_type <= IEEE80211_ENC_TYPE)
		return 0;

	if(atbm_skb_headroom(skb) < WSM_TX_EXTRA_HEADROOM+iv_len){
		atbm_printk_err("%s headroom not enough\n",__func__);
		return -2;
	}
	//atbm_printk_err("icv_len %d iv_len %d\n",icv_len,sta->key.conf.iv_len);
	hdr = (struct ieee80211_hdr *) skb->data;
	hdr->frame_control |= cpu_to_le16(IEEE80211_FCTL_PROTECTED);
	newhdr = atbm_skb_push(skb, iv_len);
	memmove(newhdr, newhdr + iv_len, ieee80211_hdrlen(hdr->frame_control));

	return 0;
}
/* Default mapping in classifier to work with default
 * queue setup.
 */
const int ieee802_1d_to_ac[8] = {
	ATBM_IEEE80211_AC_BE,
	ATBM_IEEE80211_AC_BK,
	ATBM_IEEE80211_AC_BK,
	ATBM_IEEE80211_AC_BE,
	ATBM_IEEE80211_AC_VI,
	ATBM_IEEE80211_AC_VI,
	ATBM_IEEE80211_AC_VO,
	ATBM_IEEE80211_AC_VO
};

static struct wsm_tx *atbm_tx_h_wsm(struct sta_info *sta,struct sk_buff *skb,struct atbm_vif *vif)
{
	struct wsm_tx *wsm;
	u8 queueid = ieee802_1d_to_ac[skb->priority & 7];
	enum ieee80211_enc_type enc_type; 
	u8 icv_len;
	u32 aid;
	
	if(sta == NULL){
		enc_type = vif->group_key.key_type;
		icv_len  = vif->group_key.conf.icv_len;
	}else {
		enc_type = sta->key.key_type;
		icv_len  = sta->key.conf.icv_len;
	}
	
	if(enc_type <= IEEE80211_ENC_TYPE)
		icv_len = 0;
	if(enc_type == IEEE80211_ENC_TKIP)
		icv_len += 8;

	if (sta == NULL){
		aid = 0;
	}else {
		aid = sta->sta.aid;
	}

	wsm = (struct wsm_tx *)atbm_skb_push(skb, sizeof(struct wsm_tx));
	memset(wsm, 0, sizeof(*wsm));
	wsm->hdr.len = __cpu_to_le16(skb->len + icv_len);
	wsm->hdr.id = __cpu_to_le16(WSM_TRANSMIT_REQ_MSG_ID);
	wsm->queueId =(aid << 2) | wsm_queue_id_to_wsm(queueid);
	wsm->hdr.id |= cpu_to_le16(WSM_TX_IF_ID(vif->if_id));
	wsm->htTxParameters = WSM_TX_LINUX_HOST;
	return wsm;
}
static int
atbm_tx_h_align(struct atbm_vif *priv,
		  struct sk_buff *skb,
		  u8 *flags)
{
	u32 offset = (unsigned long)(skb->data) & (u32)3;

	if (!offset)
		return 0;

	if (offset & 1) {
		atbm_printk_err(
			"Bug: attempt to transmit a frame "
			"with wrong alignment: %d\n",
			offset);
		return -EINVAL;
	}

	if (atbm_skb_headroom(skb) < offset) {
		atbm_printk_err(
			"Bug: no space allocated "
			"for DMA alignment.\n"
			"headroom: %d\n",
			atbm_skb_headroom(skb));
		return -ENOMEM;
	}
	atbm_skb_push(skb, offset);
	*flags |= WSM_TX_2BYTES_SHIFT;
	return 0;
}
static int atbm_tx_h_rate_policy(struct sta_info *sta,
			struct sk_buff *skb,
			struct wsm_tx *wsm)
{	
	/*
	*only surport one stream
	*/
	if(sta == NULL){
		wsm->maxTxRate = RATE_INDEX_B_11M;
		return 0;
	}
	if(sta->bgnMode&STA_11N_MODE){
		wsm->maxTxRate = RATE_INDEX_N_39M;//MCS7
		wsm->flags |= 1<<4;//set rate policy
	}
	else if(sta->bgnMode&STA_11G_MODE){
		wsm->maxTxRate = RATE_INDEX_A_36M;//54M
	
	}else {
		wsm->maxTxRate = RATE_INDEX_B_11M;
	}

	if(sta->bgnMode & STA_11N_MODE){
		wsm->htTxParameters |= cpu_to_le32(WSM_HT_TX_MIXED);
	}
	if(sta->shortGI){
		wsm->htTxParameters |= cpu_to_le32(WSM_HT_TX_SGI);
	}
	return 0;
}
static int
atbm_tx_h_skb_pad(struct atbm_common *priv,
		    struct wsm_tx *wsm,
		    struct sk_buff *skb)
{
	u32 len = __le16_to_cpu(wsm->hdr.len);
	u32 padded_len = priv->sbus_ops->align_size(priv->sbus_priv, len);

	if (WARN_ON(atbm_skb_padto(skb, padded_len) != 0)) {
		return -EINVAL;
	}
	return 0;
}

void atbm_tx(struct atbm_vif *vif, struct sk_buff *skb)
{
	struct atbm_vif *priv = vif;
	struct atbm_common *hw_priv = vif->hw_priv;
	struct sta_info *sta;
	struct wsm_tx *wsm;
	u8 flags = 0;
	int ret;
	struct ieee80211_hdr *frame = (struct ieee80211_hdr *)skb->data;
	
	if (!skb->data)
		BUG_ON(1);

	
	if (!priv)
		goto drop;
	
	if (atomic_read(&priv->enabled) == 0){
		atbm_printk_err("%s:if_id(%d) not enable\n",__func__,priv->if_id);
		goto drop;
	}
	if (WARN_ON(skb_get_queue_mapping(skb) >= 4)){
		atbm_printk_err("%s:if_id(%d) queue err\n",__func__,priv->if_id);
		goto drop;
	}
	sta = sta_info_get(vif,frame->addr1);
	
	if(sta == NULL){
	//	atbm_printk_err("sta is null[%pM]\n",frame->addr1);
		if(vif->type == NL80211_IFTYPE_STATION){
			atbm_printk_err("%s:[%pM] not associat\n",__func__,frame->addr1);
			goto drop;
		}else if(vif->type == NL80211_IFTYPE_AP){
			if(!is_multicast_ether_addr(frame->addr1)){
				atbm_printk_err("%s:[%pM] not associat\n",__func__,frame->addr1);
				goto drop;
			}
		}
	}
	ret = atbm_tx_h_crypt(sta,skb,vif);
	if (ret){	
		atbm_printk_err("%s:if_id(%d) crypt err\n",__func__,priv->if_id);
		goto drop;
	}
	ret = atbm_tx_h_align(priv, skb, &flags);
	if (ret){
		atbm_printk_err("%s:align drop\n",__func__);
		goto drop;
	}
	wsm = atbm_tx_h_wsm(sta, skb,vif);
	if (!wsm) {
		atbm_printk_err("%s:wsm drop\n",__func__);
		ret = -ENOMEM;
		goto drop;
	}
	wsm->flags |= flags;
	ret = atbm_tx_h_rate_policy(sta, skb, wsm);
	if (ret){
		atbm_printk_err("%s:rate drop\n",__func__);
		ret = -1;
		goto drop;
	}
	wsm->htTxParameters &= ~(__cpu_to_le32(WSM_NEED_TX_CONFIRM));
	
	ret = atbm_tx_h_skb_pad(hw_priv, wsm, skb);
	if (ret){		
		atbm_printk_err("%s:pad drop\n",__func__);
		ret = -2;
		goto drop;
	}
	atbm_submit_package(hw_priv,skb);

	return;
drop:
	atbm_dev_kfree_skb(skb);
	return;
}
void atbm_rx_cb(struct atbm_vif *priv,
		  struct wsm_rx *arg,
		  struct sk_buff **skb_p)
{
	struct atbm_common *hw_priv = ABwifi_vifpriv_to_hwpriv(priv);
	struct sk_buff *skb = *skb_p;
	struct ieee80211_rx_status *hdr = IEEE80211_SKB_RXCB(skb);
	struct ieee80211_hdr *frame = (struct ieee80211_hdr *)skb->data;
	struct atbm_ieee80211_mgmt *mgmt = (struct atbm_ieee80211_mgmt *)skb->data;
#ifdef CONFIG_PM
	unsigned long grace_period;
#endif

	hdr->flag = 0;
	
	if (unlikely(arg->status)) {
		if (arg->status == WSM_STATUS_MICFAILURE) {
			atbm_printk_err( "[RX] MIC failure. ENCRYPTION [%d][%pM][%pM]\n",
				WSM_RX_STATUS_ENCRYPTION(arg->flags),frame->addr1,frame->addr2);
			hdr->flag |= RX_FLAG_MMIC_ERROR;
		} else if (arg->status == WSM_STATUS_NO_KEY_FOUND) {
			atbm_printk_err( "[RX] No key found.ENCRYPTION [%d]\n",WSM_RX_STATUS_ENCRYPTION(arg->flags));
			goto drop;
		} else {
			atbm_printk_err("[RX] Receive failure: %d.ENCRYPTION [%d],fc(%x)\n",
				arg->status,WSM_RX_STATUS_ENCRYPTION(arg->flags),mgmt->frame_control);
			goto drop;
			
		}
	}
#ifdef CHKSUM_HW_SUPPORT
	else {
		
		//atbm_printk_err( "arg->flags(%x)\n",arg->flags);
		if (arg->flags & WSM_RX_STATUS_CHKSUM_ERROR){
			//hdr->flag &=~RX_FLAG_HW_CHKSUM_ERROR;
			hdr->flag |= RX_FLAG_HW_CHKSUM_ERROR;
		}else{
			hdr->flag &=~RX_FLAG_HW_CHKSUM_ERROR;
		}
	}	
#endif
	if (skb->len < sizeof(struct ieee80211_pspoll)) {
		atbm_printk_err( "(skb->len < sizeof(struct ieee80211_pspoll),seq(%x)\n",frame->seq_ctrl);
		goto drop;
	}

	hdr->mactime = 0; /* Not supported by WSM */
	hdr->band = (arg->channelNumber > 14) ?
			IEEE80211_BAND_5GHZ : IEEE80211_BAND_2GHZ;
	hdr->freq = ieee80211_channel_to_frequency(
			arg->channelNumber,
			hdr->band);

	if (arg->rxedRate >= 14) {
		hdr->flag |= RX_FLAG_HT;
		hdr->rate_idx = arg->rxedRate - 14;
	} else if (arg->rxedRate >= 4) {
		if (hdr->band == IEEE80211_BAND_5GHZ)
			hdr->rate_idx = arg->rxedRate - 6;
		else
			hdr->rate_idx = arg->rxedRate - 2;
	} else {
		hdr->rate_idx = arg->rxedRate;
	}

	hdr->signal = (s8)arg->rcpiRssi;
	hdr->antenna = 0;
	if(ieee80211_has_protected(frame->frame_control))
		hdr->flag |= RX_FLAG_DECRYPTED;
	if (arg->status == WSM_STATUS_MICFAILURE) {
		hdr->flag |= RX_FLAG_IV_STRIPPED;
	}
#ifdef CONFIG_PM

	/* Stay awake for 1sec. after frame is received to give
	 * userspace chance to react and acquire appropriate
	 * wakelock. */
	if (ieee80211_is_auth(frame->frame_control))
		grace_period = 5 * HZ;
	else if (ieee80211_is_deauth(frame->frame_control))
		grace_period = 5 * HZ;
	else 
		grace_period = 0;
	if(grace_period != 0)
		atbm_pm_stay_awake(&hw_priv->pm_state, grace_period);
#endif
	local_bh_disable();
	ieee80211_rx(priv,skb);
	local_bh_enable();
	*skb_p = NULL;

	return;

drop:
	/* TODO: update failure counters */
	return;
}
