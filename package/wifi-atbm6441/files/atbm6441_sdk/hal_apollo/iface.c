/*
 * O(1) TX queue with built-in allocator for altobeam APOLLO drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on apollo code
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifdef LINUX_OS
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/kernel.h>
#include <linux/if_arp.h>
#include <linux/netdevice.h>
#include <linux/rtnetlink.h>
#include <net/atbm_mac80211.h>
#include <net/ieee80211_radiotap.h>
#endif
#include "apollo.h"
#include "iface.h"
#include "ieee80211_i.h"
#include "txrx.h"
#include "debug.h"

enum work_action {
	WORK_ACT_MISMATCH,
	WORK_ACT_NONE,
	WORK_ACT_TIMEOUT,
	WORK_ACT_DONE,
	WORK_ACT_ASSOCIAT,
	WORK_ACT_DEAUTHEN,
};

void atbm_get_connectconfig(struct atbm_common *hw_priv);
void atbm_set_tcp_port_filter(struct atbm_common *hw_priv);
int atbm_notify_sta_connect_ok(struct atbm_common *hw_priv);

#ifndef CONFIG_ATBM_SDIO_ATCMD
void ieee80211_send_auth(struct        atbm_vif *vif,
			 u16 transaction, u16 auth_alg,
			 u8 *extra, size_t extra_len, const u8 *bssid,
			 const u8 *key, u8 key_len, u8 key_idx)
{
	struct atbm_common *hw_priv = vif->hw_priv;
	struct sk_buff *skb;
	struct atbm_ieee80211_mgmt *mgmt;
#ifdef CONFIG_ATBM_USE_SW_ENC
	int err;
#endif

	skb = atbm_dev_alloc_skb(hw_priv->extra_tx_headroom +
			    sizeof(*mgmt) + 6 + extra_len);
	if (!skb)
		return;

	atbm_skb_reserve(skb, hw_priv->extra_tx_headroom);

	mgmt = (struct atbm_ieee80211_mgmt *) atbm_skb_put(skb, 24 + 6);
	memset(mgmt, 0, 24 + 6);
	mgmt->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					  IEEE80211_STYPE_AUTH);
	memcpy(mgmt->da, bssid, ETH_ALEN);
	memcpy(mgmt->sa, vif->addr, ETH_ALEN);
	memcpy(mgmt->bssid, bssid, ETH_ALEN);
	mgmt->u.auth.auth_alg = cpu_to_le16(auth_alg);
	mgmt->u.auth.auth_transaction = cpu_to_le16(transaction);
	mgmt->u.auth.status_code = cpu_to_le16(0);
 	atbm_printk_always( "%s %d transaction =%d,key_idx %d,key <%s> \n",__func__,__LINE__,transaction,key_idx,key);
	rcu_read_lock();
	atbm_tx(vif, skb);
	rcu_read_unlock();
}	
static void ieee80211_send_assoc(struct atbm_vif *vif,
				 u8 *bssid)
{
	struct sk_buff *skb;
	struct atbm_ieee80211_mgmt *mgmt;
	u8 *pos, qos_info = 0;
	int i, count, rates_len, supp_rates_len;
	u16 capab;
	u32 rates = 0;
	struct sta_info *sta;
	static int atbm_rates[] = {10,20,55,110,60,90,120,180,240,360,480,540};
	
	struct ieee80211_sta_ht_cap ht_cap = {
		.cap = IEEE80211_HT_CAP_GRN_FLD |
			IEEE80211_HT_CAP_SUP_WIDTH_20_40 |
			IEEE80211_HT_CAP_DSSSCCK40 |
			(1 << IEEE80211_HT_CAP_RX_STBC_SHIFT),
		.ht_supported = 1,
		.ampdu_factor = IEEE80211_HT_MAX_AMPDU_32K,
		.ampdu_density = IEEE80211_HT_MPDU_DENSITY_NONE,
		.mcs = {
			.rx_mask[0] = 0xFF,
			.rx_highest = __cpu_to_le16(0),
			.tx_params = IEEE80211_HT_MCS_TX_DEFINED,
		},
	};
	rcu_read_lock();
	sta = sta_info_get(vif,bssid);

	if(sta == NULL){
		goto exit;
	}
	/*
	 * In case AP not provide any supported rates information
	 * before association, we send information element(s) with
	 * all rates that we support.
	 */
	rates = ~0;
	rates_len = 12;

	skb = atbm_alloc_skb(vif->hw_priv->extra_tx_headroom +
			sizeof(*mgmt) + 1000,
			GFP_KERNEL);
	if (!skb){
		goto exit;
		return;
	}

	atbm_skb_reserve(skb, vif->hw_priv->extra_tx_headroom);

	capab = WLAN_CAPABILITY_ESS;
	capab |= WLAN_CAPABILITY_SHORT_SLOT_TIME;
	capab |= WLAN_CAPABILITY_SHORT_PREAMBLE;
	
	mgmt = (struct atbm_ieee80211_mgmt *) atbm_skb_put(skb, 24);
	memset(mgmt, 0, 24);
	memcpy(mgmt->da,bssid, ETH_ALEN);
	memcpy(mgmt->sa, vif->addr, ETH_ALEN);
	memcpy(mgmt->bssid, bssid, ETH_ALEN);

	atbm_skb_put(skb, 4);
	mgmt->frame_control = cpu_to_le16(IEEE80211_FTYPE_MGMT |
					  IEEE80211_STYPE_ASSOC_REQ);
	mgmt->u.assoc_req.capab_info = cpu_to_le16(capab);
	mgmt->u.assoc_req.listen_interval =
			cpu_to_le16(0);

	/* SSID */
	pos = atbm_skb_put(skb, 2 + vif->ap_info.ssid_len);
	*pos++ = ATBM_WLAN_EID_SSID;
	*pos++ = vif->ap_info.ssid_len;
	memcpy(pos, vif->ap_info.ssid, vif->ap_info.ssid_len);

	/* add all rates which were marked to be used above */
	supp_rates_len = rates_len;
	if (supp_rates_len > 8)
		supp_rates_len = 8;

	pos = atbm_skb_put(skb, supp_rates_len + 2);
	*pos++ = ATBM_WLAN_EID_SUPP_RATES;
	*pos++ = supp_rates_len;

	count = 0;
	for (i = 0; i < rates_len; i++) {
		if (BIT(i) & rates) {
			int rate = atbm_rates[i];
			if(i<4){
				*pos++ = (u8) ((rate / 5)|0x80);
			}else{
				*pos++ = (u8) (rate / 5);
			}
			if (++count == 8)
				break;
		}
	}

	if (rates_len > count) {
		pos = atbm_skb_put(skb, rates_len - count + 2);
		*pos++ = ATBM_WLAN_EID_EXT_SUPP_RATES;
		*pos++ = rates_len - count;

		for (i++; i < rates_len; i++) {
			if (BIT(i) & rates) {
				int rate = atbm_rates[i];
				*pos++ = (u8)(rate / 5);
			}
		}
	}

	//case IEEE80211_SMPS_OFF:
	capab = ht_cap.cap;
		
	/* reserve and fill IE */
	*pos++ = ATBM_WLAN_EID_HT_CAPABILITY;
	*pos++ = sizeof(struct ieee80211_ht_cap);
	memset(pos, 0, sizeof(struct ieee80211_ht_cap));

	/* capability flags */
	capab = cpu_to_le16(ht_cap.cap);
	memcpy(pos, &capab, sizeof(u16));
	pos += sizeof(u16);

	/* AMPDU parameters */
	*pos++ = ht_cap.ampdu_factor |
		    (ht_cap.ampdu_density<<
			IEEE80211_HT_AMPDU_PARM_DENSITY_SHIFT);

	/* MCS set */
	memcpy(pos, &ht_cap.mcs, sizeof(ht_cap.mcs));
	pos += sizeof(ht_cap.mcs);

	/* extended capabilities */
	pos += sizeof(u16);

	/* BF capabilities */
	pos += sizeof(u16);

	/* antenna selection */
	pos += sizeof(u8);


	if (1) {
		pos = atbm_skb_put(skb, 9);
		*pos++ = ATBM_WLAN_EID_VENDOR_SPECIFIC;
		*pos++ = 7; /* len */
		*pos++ = 0x00; /* Microsoft OUI 00:50:F2 */
		*pos++ = 0x50;
		*pos++ = 0xf2;
		*pos++ = 2; /* WME */
		*pos++ = 0; /* WME info */
		*pos++ = 1; /* WME ver */
		*pos++ = qos_info;
	}
	atbm_tx(vif, skb);
exit:
	rcu_read_unlock();
}

static enum work_action 
ieee80211_rx_mgmt_auth(struct atbm_vif *vif,struct atbm_ieee80211_mgmt *mgmt, size_t len)
{
	u16 auth_alg, auth_transaction, status_code;

	auth_alg = le16_to_cpu(mgmt->u.auth.auth_alg);
	auth_transaction = le16_to_cpu(mgmt->u.auth.auth_transaction);
	status_code = le16_to_cpu(mgmt->u.auth.status_code);

	if (status_code != WLAN_STATUS_SUCCESS) {
		atbm_printk_err("%s: %pM denied authentication (status %d)\n",
		       __func__, mgmt->sa, status_code);
		return WORK_ACT_DONE;
	}


	atbm_printk_always("%s: authenticated\n",__func__);
	return WORK_ACT_ASSOCIAT;
}
static enum work_action __must_check
ieee80211_rx_mgmt_assoc_resp(struct atbm_vif *vif,
			     struct atbm_ieee80211_mgmt *mgmt, size_t len,
			     bool reassoc)
{
	u16 capab_info, status_code, aid;
	/*
	 * AssocResp and ReassocResp have identical structure, so process both
	 * of them in this function.
	 */

	if (len < 24 + 6)
		return WORK_ACT_NONE;

	capab_info = le16_to_cpu(mgmt->u.assoc_resp.capab_info);
	status_code = le16_to_cpu(mgmt->u.assoc_resp.status_code);
	aid = le16_to_cpu(mgmt->u.assoc_resp.aid);

	atbm_printk_always("%s: RX %sssocResp from %pM (capab=0x%x "
	       "status=%d aid=%d)\n",
	       __func__, reassoc ? "Rea" : "A", mgmt->sa,
	       capab_info, status_code, (u16)(aid & ~(BIT(15) | BIT(14))));

	if (status_code != WLAN_STATUS_SUCCESS)
		atbm_printk_err( "%s: %pM denied association (code=%d)\n",
		       __func__, mgmt->sa, status_code);
	else{
		struct sta_info *sta;
		mutex_lock(&vif->hw_priv->sta_mtx);
		sta = sta_info_get(vif,mgmt->bssid);
		if(sta){
			set_sta_flag(sta, WLAN_STA_ASSOC);
			set_sta_flag(sta,WLAN_STA_AUTHORIZED);
			netif_carrier_on(vif->ndev);			
			atbm_printk_always( "%s: associated\n", __func__);
		}
		mutex_unlock(&vif->hw_priv->sta_mtx);
	}
	
	return WORK_ACT_DONE;
}
static void ieee80211_sta_rx_queued_mgmt(struct atbm_vif *vif,
				  struct sk_buff *skb)
{
	struct ieee80211_rx_status *rx_status;
	struct atbm_ieee80211_mgmt *mgmt;
	u16 fc;
	enum work_action rma = WORK_ACT_NONE;
	rx_status = (struct ieee80211_rx_status *) skb->cb;
	mgmt = (struct atbm_ieee80211_mgmt *) skb->data;
	fc = le16_to_cpu(mgmt->frame_control);

	switch (fc & IEEE80211_FCTL_STYPE) {
	case IEEE80211_STYPE_BEACON:
	case IEEE80211_STYPE_PROBE_RESP:
//		atbm_printk_err("%s:beacon and probe response do not process\n",__func__);
		break;
	case IEEE80211_STYPE_AUTH:
		rma = ieee80211_rx_mgmt_auth(vif,mgmt,skb->len);
		break;
	case IEEE80211_STYPE_ASSOC_RESP:
		rma = ieee80211_rx_mgmt_assoc_resp(vif, mgmt,
							   skb->len, false);
		break;
	case IEEE80211_STYPE_DEAUTH:
		rma = WORK_ACT_DEAUTHEN;
		break;
	case IEEE80211_STYPE_DISASSOC:
		rma = WORK_ACT_DEAUTHEN;
		break;
	case IEEE80211_STYPE_ACTION:
		{
		break;
		}
	}

	switch (rma) {
	case WORK_ACT_NONE:
		/* no action */
		break;
	case WORK_ACT_ASSOCIAT:
		ieee80211_send_assoc(vif,vif->ap_info.bssid);
		break;
	case WORK_ACT_DEAUTHEN:
		break;
	default:
		WARN(1, "unexpected: %d", rma);
	}
	return;
	
}
static void atbm_sta_key_config(struct ieee80211_key *key,u8 key_type)
{
	switch(key_type){
	case ATBM_WLAN_CIPHER_SUITE_WEP40:
	case ATBM_WLAN_CIPHER_SUITE_WEP104:
		key->key_type = IEEE80211_ENC_WEP;
		key->conf.iv_len = WEP_IV_LEN;
		key->conf.icv_len = WEP_ICV_LEN;
		break;
	case ATBM_WLAN_CIPHER_SUITE_TKIP:
		key->key_type = IEEE80211_ENC_TKIP;
		key->conf.iv_len = TKIP_IV_LEN;
		key->conf.icv_len = TKIP_ICV_LEN;
		break;
	case ATBM_WLAN_CIPHER_SUITE_CCMP:
		key->key_type = IEEE80211_ENC_AES;
		key->conf.iv_len = CCMP_HDR_LEN;
		key->conf.icv_len = CCMP_MIC_LEN;
		
		break;
	case ATBM_WLAN_CIPHER_SUITE_AES_CMAC:
		key->key_type = IEEE80211_ENC_AES_CMAC;
		key->conf.iv_len = 0;
		key->conf.icv_len = sizeof(struct ieee80211_mmie);
		break;
	default:
		atbm_printk_err("%s:%d not support\n",__func__,key_type);
	}
}
void atbm_sta_connect_event(struct atbm_vif *vif,struct HostConnectEvent * hostevent)
{
	struct sta_info *sta;
	int ret = 0;
	u8 bgnMode = hostevent->bgnMode;
	sta = sta_info_alloc(vif, (u8 *)hostevent->bssid, GFP_KERNEL);
	if (!sta){
		ret = -ENOMEM;
		goto exit;
	}

	ret = sta_info_insert_rcu(sta);
	if (ret) {
		rcu_read_unlock();
		goto exit;
	}
	rcu_read_unlock();

	mutex_lock(&vif->hw_priv->sta_mtx);
	sta->sta.ht_cap.ht_supported  = !!(bgnMode&STA_11N_MODE);
	sta->bgnMode= bgnMode;
	sta->wmm = !!(hostevent->connect_flag&CONNECT_FLAG_WMM);
	set_sta_flag(sta, WLAN_STA_ASSOC);
	set_sta_flag(sta,WLAN_STA_AUTHORIZED);
	sta->enc = hostevent->crypto_pairwise != 0 ? true:false;
	vif->ap_info.enc = sta->enc;
	if(sta->enc == true){
		atbm_sta_key_config(&sta->key,hostevent->crypto_pairwise);
		atbm_sta_key_config(&vif->group_key,hostevent->crypto_group);
	}
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	atbm_set_ak_ip_info(vif->ndev, &hostevent->ipaddr, &hostevent->ipmask, &hostevent->gwaddr);
#endif
	netif_carrier_on(vif->ndev);			
	atbm_printk_always( "%s: associated\n", __func__);
	vif->connect_success =1;
	memcpy(vif->ap_info.bssid,hostevent->bssid,6);
	memset(vif->ptk_pn, 0, sizeof(vif->ptk_pn));
	memset(vif->ptk_pn_init, 1, sizeof(vif->ptk_pn_init));
	memset(vif->ptk_noqos_pn, 0, CCMP_PN_LEN);
	vif->ptk_noqos_pn_init= 1;
	memset(vif->gtk_pn, 0, CCMP_PN_LEN);
	vif->gtk_pn_init= 1;
	mutex_unlock(&vif->hw_priv->sta_mtx);
	atbm_notify_sta_connect_ok(vif->hw_priv);
exit:
	return ;

}

void atbm_sta_disconnect_event(struct atbm_vif *vif,u8 *bssid)
{
	struct sta_info *sta;
	int ret = 0;
	sta = sta_info_get(vif,bssid);
	if (!sta){
		ret = -ENOMEM;
		goto exit;
	}
	mutex_lock(&vif->hw_priv->sta_mtx);

	clear_sta_flag(sta, WLAN_STA_ASSOC);
	clear_sta_flag(sta,WLAN_STA_AUTHORIZED);
	__sta_info_destroy(sta);
	netif_carrier_off(vif->ndev);			
	atbm_printk_always( "%s: deauth\n", __func__);
	vif->connect_success =0;
	mutex_unlock(&vif->hw_priv->sta_mtx);
exit:
	return ;
}

static struct wsm_sta_list_req sta_list_old = {0};
//call in ap mode
int atbm_get_checked_sta(struct atbm_vif*vif, u8 *mac_addr, u8 *sta_cnt, u8 b_add)
{
	int ret = 0;
	int mac_size = sizeof(sta_list_old.info[0].macAddr);
	int get_mac = 0;
	struct wsm_sta_list_req sta_list;
	int i,j;

	if (mac_addr == NULL){
		printk("mac_addr is null.\n");
		return -1;
	}

	memset(&sta_list, 0, sizeof(sta_list));
	ret = wsm_get_stalist(vif->hw_priv, &sta_list, sizeof(sta_list));
	if (ret){
		printk("get sta list err.\n");
		return -1;
	}

	if (b_add){
		for (i=0; i<sta_list.sta_cnt; i++){
			for (j=0; j<sta_list_old.sta_cnt; j++){
				if (!memcmp(sta_list_old.info[j].macAddr, sta_list.info[i].macAddr, mac_size)){
					break;
				}
			}
			if (sta_list_old.sta_cnt == 0 || j == sta_list_old.sta_cnt){
				memcpy(mac_addr, sta_list.info[i].macAddr, mac_size);
				get_mac = 1;
				break;
			}
		}
	}
	else {
		for (i=0; i<sta_list_old.sta_cnt; i++){
			for (j=0; j<sta_list.sta_cnt; j++){
				if (!memcmp(sta_list_old.info[i].macAddr, sta_list.info[j].macAddr, mac_size)){
					break;
				}
			}
			if (sta_list.sta_cnt == 0 || j == sta_list.sta_cnt){
				memcpy(mac_addr, sta_list_old.info[i].macAddr, mac_size);
				get_mac = 1;
				break;
			}
		}
	}

	memcpy(&sta_list_old, &sta_list, sizeof(sta_list));

	if (sta_cnt != NULL){
		*sta_cnt = sta_list_old.sta_cnt;
	}

	if (get_mac){
		return 0;
	}

	return -1;
}

void atbm_sta_add_event(struct atbm_vif *vif, int link_id)
{
	struct sta_info *sta;
	int ret = 0;
	u8 mac_addr[6];
	u8 sta_cnt;

	ret = atbm_get_checked_sta(vif, mac_addr, &sta_cnt, 1);
	if (ret){
		goto exit;
	}

	printk("%s  mac_addr:%pM\n", __func__, mac_addr);
	
	sta = sta_info_alloc(vif, mac_addr, GFP_KERNEL);
	if (!sta){
		ret = -ENOMEM;
		goto exit;
	}

	ret = sta_info_insert_rcu(sta);
	if (ret) {
		rcu_read_unlock();
		goto exit;
	}
	rcu_read_unlock();

	mutex_lock(&vif->hw_priv->sta_mtx);
	sta->sta.aid = link_id;
	sta->wmm = !!(1&CONNECT_FLAG_WMM);
	set_sta_flag(sta, WLAN_STA_ASSOC);
	set_sta_flag(sta,WLAN_STA_AUTHORIZED);
	memcpy(&sta->key,&vif->ap_info.key,sizeof(struct ieee80211_key));
	if(sta->key.key_type > IEEE80211_ENC_TYPE )
		sta->enc=true;
	atbm_printk_err("add[%pM],aid[%d],enc[%d],key_type(%d),iv(%d),icv(%d)\n",mac_addr,sta->sta.aid,sta->enc,sta->key.key_type,
	sta->key.conf.iv_len,sta->key.conf.icv_len);
	if (sta_cnt == 1){
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
		//atbm_set_ak_ip_info(vif->ndev, &ipaddr, &ipmask, &gwaddr);
#endif
		netif_carrier_on(vif->ndev);
		vif->connect_success = 1;
	}
	mutex_unlock(&vif->hw_priv->sta_mtx);
exit:
	return ;
}

void atbm_sta_loss_event(struct atbm_vif *vif)
{
	struct sta_info *sta;
	int ret = 0;
	u8 mac_addr[6];
	u8 sta_cnt;

	ret = atbm_get_checked_sta(vif, mac_addr, &sta_cnt, 0);
	if (ret){
		goto exit;
	}

	printk("%s  mac_addr:%pM\n", __func__, mac_addr);

	sta = sta_info_get(vif,mac_addr);
	if (!sta){
		ret = -ENOMEM;
		goto exit;
	}

	mutex_lock(&vif->hw_priv->sta_mtx);
	clear_sta_flag(sta, WLAN_STA_ASSOC);
	clear_sta_flag(sta,WLAN_STA_AUTHORIZED);
	__sta_info_destroy(sta);
	if (sta_cnt == 0){
		netif_carrier_off(vif->ndev);			
		vif->connect_success = 0;
	}
	mutex_unlock(&vif->hw_priv->sta_mtx);
exit:
	return ;
}

static void ieee80211_iface_work(struct work_struct *work)
{
	struct atbm_vif *vif =
		container_of(work, struct atbm_vif, work);
	struct atbm_common *hw_priv = vif->hw_priv;
	struct sk_buff *skb;
	struct sta_info *sta;
	
	if (!atomic_read(&vif->enabled)){
		atbm_printk_err("%s:not runnning\n",__func__);
		return;
	}
	/* first process frames */
	while ((skb = atbm_skb_dequeue(&vif->skb_queue))) {
		struct atbm_ieee80211_mgmt *mgmt = (void *)skb->data;
		if(0){}
		else if (ieee80211_is_action(mgmt->frame_control) &&
			   mgmt->u.action.category == WLAN_CATEGORY_BACK) {
			int len = skb->len;

			mutex_lock(&hw_priv->sta_mtx);
			sta = sta_info_get(vif, mgmt->sa);
			if (sta) {
				switch (mgmt->u.action.u.addba_req.action_code) {
				case WLAN_ACTION_ADDBA_REQ:
					ieee80211_process_addba_request(
							hw_priv, sta, mgmt, len);
					break;
				case WLAN_ACTION_DELBA:
					ieee80211_process_delba(vif, sta,
								mgmt, len);
					break;
				default:
					WARN_ON(1);
					break;
				}
			}
			mutex_unlock(&hw_priv->sta_mtx);
		} else if (ieee80211_is_data_qos(mgmt->frame_control)) {
			WARN_ON(1);
			/*
			*here can not stop rx agg,because lmac will handle the agg process
			*/
		} else if(ieee80211_is_mgmt(mgmt->frame_control)){
			switch (vif->type) {
			case NL80211_IFTYPE_AP:
			case NL80211_IFTYPE_P2P_GO:
				break;
			case NL80211_IFTYPE_STATION:
				ieee80211_sta_rx_queued_mgmt(vif,skb);
				break;
			default:
				WARN(1, "for unkown if");
				break;
			}

		}
		atbm_kfree_skb(skb);
	}
}

static int atbm_open(struct net_device *dev)
{
	struct atbm_vif *sdata = atbm_dev_to_vif(dev);
	atomic_set(&sdata->enabled,1);
	
	atbm_get_connectconfig(sdata->hw_priv);
	atbm_set_tcp_port_filter(sdata->hw_priv);

	if(sdata->connect_success==0){
		netif_carrier_off(dev);
	}
	else {
		netif_carrier_on(dev);
	}
	netif_tx_start_all_queues(dev);
	spin_lock_bh(&sdata->hw_priv->tx_queue_lock);
	sdata->hw_priv->tx_queue_overfull = false;
	spin_unlock_bh(&sdata->hw_priv->tx_queue_lock);
	atbm_printk_always("%s\n",__func__);
	//atbm_vif_connect(sdata);
	return 0;
}

static int atbm_stop(struct net_device *dev)
{
	struct atbm_vif *vif = atbm_dev_to_vif(dev);
	
	atomic_set(&vif->enabled,0);
	netif_tx_stop_all_queues(dev);
	sta_info_flush(vif->hw_priv,vif);
	flush_work(&vif->work);
	/*
	 * When we get here, the interface is marked down.
	 * Call synchronize_rcu() to wait for the RX path
	 * should it be using the interface and enqueuing
	 * frames at this very time on another CPU.
	 */
	synchronize_rcu();
	atbm_skb_queue_purge(&vif->skb_queue);	
	atbm_printk_always("%s\n",__func__);
	return 0;
}
static void atbm_sdata_uninit(struct net_device *dev)
{
	struct atbm_vif *vif = atbm_dev_to_vif(dev);
	sta_info_flush(vif->hw_priv, vif);
}

static int ieee80211_skb_resize(struct sk_buff *skb,
				int head_need, bool may_encrypt)
{
	int tail_need = 0;

	if (atbm_skb_cloned(skb))
		;
	else if (head_need || tail_need)
		;
	else
		return 0;

	if (atbm_pskb_expand_head(skb, head_need, tail_need, GFP_ATOMIC)) {
		atbm_printk_debug("failed to reallocate TX buffer\n");
		return -ENOMEM;
	}

	return 0;
}
void atbm_set_qos_hdr(struct atbm_vif *vif,
			   struct sk_buff *skb)
{
	struct ieee80211_hdr *hdr = (void *)skb->data;

	/* Fill in the QoS header if there is one. */
	if (ieee80211_is_data_qos(hdr->frame_control)) {
		u8 *p = ieee80211_get_qos_ctl(hdr);
		u8 ack_policy, tid;

		tid = skb->priority & IEEE80211_QOS_CTL_TAG1D_MASK;

		/* preserve EOSP bit */
		ack_policy = *p & IEEE80211_QOS_CTL_EOSP;

		/* qos header is 2 bytes */
		*p++ = ack_policy | tid;
		*p =  0;
	}
}

struct atbm_ip_addr {
	u32 addr;
}__packed;

struct atbm_ip_hdr {
  /* version / header length / type of service */
  u8 _v_hl;
  u8 _tos;
  /* total length */
  u16 _len;
  /* identification */
  u16 _id;
  /* fragment offset field */
  u16 _offset;
  /* time to live / protocol*/
 u8 _ttl;
 u8 _proto;
  /* checksum */
  u16 _chksum;
  /* source and destination IP addresses */
  struct atbm_ip_addr src;
  struct atbm_ip_addr dest; 
}__packed;

struct atbm_ieee8023_hdr {
	unsigned char	h_dest[ETH_ALEN];	/* destination eth addr	*/
	unsigned char	h_source[ETH_ALEN];	/* source ether addr	*/
	unsigned short	h_proto;		/* packet type ID field	*/
}__packed;

static u16 atbm_htons(u16 n)
{
  return ((n & 0xff) << 8) | ((n & 0xff00) >> 8);
}

static unsigned int atbm_cfg80211_classify8021d(struct sk_buff *skb)
{
	unsigned int dscp;
	struct atbm_ip_hdr *iphdr;
	struct atbm_ieee8023_hdr *ethhdr;
	u16 protocol = 0;

	ethhdr = (struct atbm_ieee8023_hdr *)(skb->data);
	protocol = atbm_htons(ethhdr->h_proto);

	if (protocol==ETH_P_IP){
		//dscp = (unsigned int)(atbm_skb_pull(skb,ETH_HLEN+1)) & 0xfc;
		iphdr = (struct atbm_ip_hdr *)(((u8 *)(skb->data))+ETH_HLEN);
		dscp =  iphdr->_tos & 0xfc;
	}
	else{
		return 0;
	}
	return dscp >> 5;
}

extern int is_pre_rmmod;

netdev_tx_t atbm_subif_start_xmit(struct sk_buff *skb,
				    struct net_device *dev)
{
	struct atbm_vif *vif = atbm_dev_to_vif(dev);
	struct atbm_common *hw_priv = vif->hw_priv;
	struct sta_info	*sta;
	struct ieee80211_hdr hdr;
	u16 ethertype, hdrlen;
	__le16 fc;
	int ret = NETDEV_TX_BUSY;
	const u8 *encaps_data;
	int encaps_len, skip_header_bytes;
	int nh_pos, h_pos;
	int head_need;
	struct sk_buff *tmp_skb;

	if (is_pre_rmmod) {
		ret = NETDEV_TX_OK;
		goto fail;
	}

	if (unlikely(skb->len < ETH_HLEN)) {
		ret = NETDEV_TX_OK;
		goto fail;
	}

	skb->priority = atbm_cfg80211_classify8021d(skb);

	/* convert Ethernet header to proper 802.11 header (based on
	 * operation mode) */
	ethertype = (skb->data[12] << 8) | skb->data[13];
	fc = cpu_to_le16(IEEE80211_FTYPE_DATA | IEEE80211_STYPE_DATA);

	if(vif->type == NL80211_IFTYPE_STATION){
		/* BSSID SA DA */
		fc |= cpu_to_le16(IEEE80211_FCTL_TODS);
		memcpy(hdr.addr1, vif->ap_info.bssid, ETH_ALEN);
		memcpy(hdr.addr2, skb->data + ETH_ALEN, ETH_ALEN);
		memcpy(hdr.addr3, skb->data, ETH_ALEN);
	}else if(vif->type == NL80211_IFTYPE_AP){
		fc |= cpu_to_le16(IEEE80211_FCTL_FROMDS);
		/* DA BSSID SA */
		memcpy(hdr.addr1, skb->data, ETH_ALEN);
		memcpy(hdr.addr2, vif->addr, ETH_ALEN);
		memcpy(hdr.addr3, skb->data + ETH_ALEN, ETH_ALEN);
	}else {
		atbm_printk_err("%s:mode err(%d)\n",__func__,vif->type);
		ret = NETDEV_TX_OK;
		goto fail;
	}
	hdrlen = 24;
	/*
	 * There's no need to try to look up the destination
	 * if it is a multicast address (which can only happen
	 * in AP mode)
	 */
	if (!is_multicast_ether_addr(hdr.addr1)) {
		rcu_read_lock();
		sta = sta_info_get(vif, hdr.addr1);
		if(sta && (sta->wmm == true)){
			fc |= cpu_to_le16(IEEE80211_STYPE_QOS_DATA);
			hdrlen += 2;
		}
		rcu_read_unlock();
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

	head_need = hdrlen + encaps_len  - atbm_skb_headroom(skb);

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
		head_need += hw_priv->extra_tx_headroom;
		head_need = max_t(int, 0, head_need);
		if (ieee80211_skb_resize(skb, head_need, true))
			goto fail;
	}
	if (encaps_data) {
		memcpy(atbm_skb_push(skb, encaps_len), encaps_data, encaps_len);
		nh_pos += encaps_len;
		h_pos += encaps_len;
	}

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

	atbm_set_qos_hdr(vif, skb);
	rcu_read_lock();
	atbm_tx(vif,skb);
	rcu_read_unlock();
	
	return NETDEV_TX_OK;
fail:
	atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "%s fail\n", __func__);
	if (ret == NETDEV_TX_OK)
		dev_kfree_skb(skb);

	return ret;

}

static int atbm_change_mtu(struct net_device *dev, int new_mtu)
{
	if ((new_mtu < 256) || (new_mtu>1500)) {
		return -EINVAL;
	}
	dev->mtu = new_mtu;
	return 0;
}

#ifdef LINUX_OS
#if (LINUX_VERSION_CODE > KERNEL_VERSION(5, 4, 0))
static u16 atbm_netdev_select_queue(struct net_device *dev,
										struct sk_buff *skb,	
										struct net_device *sb_dev)

#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0))
static u16 atbm_netdev_select_queue(struct net_device *dev,
										struct sk_buff *skb,
										struct net_device *sb_dev,	
										select_queue_fallback_t fallback)

#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 9, 37))
static u16 atbm_netdev_select_queue(struct net_device *dev,
										struct sk_buff *skb,
										void *accel_priv,
										select_queue_fallback_t fallback)

#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 4, 0))
static u16 atbm_netdev_select_queue(struct net_device *dev,
										struct sk_buff *skb,
										struct net_device *sb_dev,	
										select_queue_fallback_t fallback)

#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 11, 0))
static u16 atbm_netdev_select_queue(struct net_device *dev,
										struct sk_buff *skb,
										void *accel_priv,
										select_queue_fallback_t fallback)
#else
static u16 atbm_netdev_select_queue(struct net_device *dev,struct sk_buff *skb)
#endif

{
	return 0;
}
int atbm_netdev_ioctrl(struct net_device *dev, struct ifreq *rq, int cmd)
{	
	int ret = 0;
	
	return ret;
}
#endif

static const struct net_device_ops atbm_dataif_ops = {
	.ndo_open		= atbm_open,
	.ndo_stop		= atbm_stop,
	.ndo_uninit		= atbm_sdata_uninit,
	.ndo_start_xmit		= atbm_subif_start_xmit,
	.ndo_change_mtu 	= atbm_change_mtu,
#ifdef LINUX_OS
	.ndo_select_queue	= atbm_netdev_select_queue,
#if defined(CONFIG_ATBM_IOCTRL)
	.ndo_do_ioctl = atbm_netdev_ioctrl,
#endif
#endif
};

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0))
static void ieee80211_if_free(struct net_device *dev)
{
        free_percpu(dev->tstats);
}
#endif

static void atbm_if_setup(struct net_device *dev)
{
	ether_setup(dev);
	dev->priv_flags &= ~IFF_TX_SKB_SHARING;
	netdev_attach_ops(dev, &atbm_dataif_ops);
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,29))
	/* Do we need this ? */
	/* we will validate the address ourselves in ->open */
	dev->validate_addr = NULL;
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0))
        dev->needs_free_netdev = true;
        dev->priv_destructor = ieee80211_if_free;
#else
	dev->destructor = free_netdev;
#endif
}

static void atbm_setup_vifdata(struct atbm_vif *vif)
{
	atomic_set(&vif->enabled,0);
	vif->if_id = 0;
	vif->type = NL80211_IFTYPE_STATION;
	atbm_skb_queue_head_init(&vif->skb_queue);
	INIT_WORK(&vif->work, ieee80211_iface_work);
}
int atbm_netdev_add(struct atbm_common *hw_priv,const char *name)
{
	struct net_device *ndev;
	struct atbm_vif *vif = NULL;
	int ret = 0;

	ASSERT_RTNL();
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3,18,00))
	ndev = alloc_netdev_mqs(sizeof(*vif),
				name,NET_NAME_UNKNOWN, atbm_if_setup, 4, 1);
#else	
	ndev = alloc_netdev_mqs(sizeof(*vif),
				name, atbm_if_setup, 4, 1);
#endif
	if (!ndev)
		return -1;

	dev_net_set(ndev, &init_net);
#ifdef CHKSUM_HW_SUPPORT
	ndev->hw_features = (NETIF_F_RXCSUM|NETIF_F_IP_CSUM);
	ndev->features |= ndev->hw_features;
	atbm_printk_init("+++++++++++++++++++++++++++++++hw checksum open ++++++++++++++++++++\n");
#endif

#ifdef CONFIG_ATBM_SUPPORT_SG
	atbm_printk_init("enable sg\n");
	ndev->hw_features |= NETIF_F_SG;
	ndev->features    |= NETIF_F_SG;
#endif
/* This is an optimization, just ignore for older kernels */
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,26))
	ndev->needed_headroom = hw_priv->extra_tx_headroom +
				4*6 /* four MAC addresses */
				+ 2 + 2 + 2 + 2 /* ctl, dur, seq, qos */
				+ 6 /* mesh */
				+ 8 /* rfc1042/bridge tunnel */
				- ETH_HLEN /* ethernet hard_header_len */
				+ IEEE80211_ENCRYPT_HEADROOM;
	ndev->needed_tailroom = IEEE80211_ENCRYPT_TAILROOM;
#endif

	ret = dev_alloc_name(ndev, ndev->name);
	
	if(ret<0){
		goto fail;
	}
	memcpy(ndev->perm_addr, hw_priv->mac_addr, ETH_ALEN);
	memcpy(ndev->dev_addr, ndev->perm_addr, ETH_ALEN);
	SET_NETDEV_DEV(ndev,hw_priv->pdev);
	vif = netdev_priv(ndev);
	vif->hw_priv = hw_priv;
	vif->ndev    = ndev;
	memcpy(vif->addr,ndev->dev_addr,ETH_ALEN);
	atbm_setup_vifdata(vif);
	ret = register_netdevice(ndev);
	if (ret)
		goto fail;

	hw_priv->vif_list[vif->if_id] = vif;

#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	atomic_set(&vif->enabled,1);
	atbm_get_connectconfig(hw_priv);
	atbm_set_tcp_port_filter(hw_priv);
#endif
	return 0;
fail:
	free_netdev(ndev);
	return -1;
}

#else	//#ifndef CONFIG_ATBM_SDIO_ATCMD

int atbm_netdev_none(struct atbm_common *hw_priv)
{
	struct atbm_vif *vif = NULL;

	vif = kzalloc(sizeof(struct atbm_vif), GFP_KERNEL);
	vif->hw_priv = hw_priv;
	memcpy(vif->addr, hw_priv->mac_addr, ETH_ALEN);
	atomic_set(&vif->enabled,0);
	vif->if_id = 0;
	vif->type = NL80211_IFTYPE_STATION;
	atbm_skb_queue_head_init(&vif->skb_queue);

	hw_priv->vif_list[vif->if_id] = vif;
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	atomic_set(&vif->enabled,1);
#endif

	return 0;
}

#endif

void atbm_remove_interfaces(struct atbm_common *hw_priv)
{
	int i = 0;
	struct atbm_vif *vif;

	ASSERT_RTNL();
	for(i = 0;i<ATBM_WIFI_MAX_VIFS;i++){
		
		vif = hw_priv->vif_list[i];
		
		if(vif == NULL)
			continue;
		rcu_assign_pointer(hw_priv->vif_list[i],NULL);
		synchronize_rcu();
#ifndef CONFIG_ATBM_SDIO_ATCMD
		unregister_netdevice(vif->ndev);
#endif
	}
}
