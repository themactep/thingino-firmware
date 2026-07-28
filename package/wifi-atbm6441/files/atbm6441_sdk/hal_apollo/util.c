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
 * utilities for mac80211
 */

#ifdef LINUX_OS
#include <net/atbm_mac80211.h>
#include <linux/netdevice.h>
#include <linux/export.h>
#include <linux/types.h>
#include <linux/slab.h>
#include <linux/skbuff.h>
#include <linux/etherdevice.h>
#include <linux/if_arp.h>
#include <linux/bitmap.h>
#include <linux/crc32.h>
#include <net/net_namespace.h>
#include <net/cfg80211.h>
#include <net/rtnetlink.h>
#include <net/atbm_mac80211.h>
#include <linux/kthread.h>
#endif
#include "apollo.h"
#include "ieee80211_i.h"


#include "bh.h"
#include "hwio.h"
#include "wsm.h"
#include "sbus.h"
#include "apollo_plat.h"
/* Must be called from BH thraed. */
int atbm_rx_bh_flush(struct atbm_common *hw_priv)
{
	struct sk_buff *skb ;

	while ((skb = atbm_skb_dequeue(&hw_priv->rx_frame_queue)) != NULL) {
		//printk("test=====>atbm_kfree skb %p \n",skb);
		atbm_dev_kfree_skb(skb);
	}
	return 0;
}
int atbm_tx_bh_flush(struct atbm_common *hw_priv)
{
	struct sk_buff *skb ;

	while ((skb = atbm_skb_dequeue(&hw_priv->tx_frame_queue)) != NULL) {
		//printk("test=====>atbm_kfree skb %p \n",skb);
		atbm_dev_kfree_skb(skb);
	}
	return 0;
}

void atbm_enable_powersave(struct atbm_common *hw_priv,
			     bool enable)
{
	hw_priv->powersave_enabled = enable;
}

void atbm_bh_wakeup(struct atbm_common *hw_priv)
{
	if(hw_priv->sbus_ops->sbus_xmit_schedule)
		hw_priv->sbus_ops->sbus_xmit_schedule(hw_priv->sbus_priv);
}

int wsm_release_vif_tx_buffer(struct atbm_common *hw_priv, int if_id,
				int count)
{
	int ret = 0;

	return ret;
}


int wsm_release_vif_tx_buffer_Nolock(struct atbm_common *hw_priv, int if_id,
				int count)
{
	int ret = 0;

	return ret;
}
void atbm_monitor_pc(struct atbm_common *hw_priv)
{
	u32 testreg1[10] = {0};
	u32 testreg_pc = 0;
	u32 testreg_ipc = 0;
	u32 val28;
	u32 val20;
	int i = 0;

	atbm_direct_write_reg_32(hw_priv,0x16100050,1);
	//atbm_direct_read_reg_32(hw_priv,0x18e00014,&testreg1);
	atbm_direct_read_reg_32(hw_priv,0x16100054,&testreg_pc);
	atbm_direct_read_reg_32(hw_priv,0x16100058,&testreg_ipc);
	atbm_direct_read_reg_32(hw_priv,0x16101028,&val28);
	atbm_direct_read_reg_32(hw_priv,0x16101020,&val20);
	//atbm_direct_read_reg_32(hw_priv,0x16400000,&testreg_uart);

	for(i=0;i<10;i++){
		atbm_direct_read_reg_32(hw_priv,hw_priv->wsm_caps.exceptionaddr+4*i+4,&testreg1[i]);
	}
	atbm_direct_write_reg_32(hw_priv,0x16100050,0);

	atbm_printk_err("ERROR !! pc:[%x],ipc[%x] \n",testreg_pc,testreg_ipc);
	atbm_printk_err("ERROR !! reg0:[%x],reg1[%x],reg2[%x],reg3[%x],reg4[%x],reg5[%x],reg6[%x] \n",
														testreg1[0],
														testreg1[1],
														testreg1[2],
														testreg1[3],
														testreg1[4],
														testreg1[5],
														testreg1[6]);

	atbm_printk_err( "%s:0x16101028(%x)\n",__func__,val28);	
	atbm_printk_err( "%s:0x16101020(%x)\n",__func__,val20);
	
}
void atbm_xmit_linearize(struct atbm_common	*hw_priv,
	 struct wsm_tx *wsm,char *xmit,int xmit_len,struct sk_buff *skb)
{
	while((skb != NULL)&&(skb_is_nonlinear(skb))){
		
		int sg_len = 0;
		int sg = 0;

		BUG_ON((void *)skb->data != (void *)wsm);		
		printk_once(KERN_ERR "sg process\n");

		memcpy(xmit,skb->data,skb_headlen(skb));

		sg_len += skb_headlen(skb);
		xmit += sg_len;
#ifdef LINUX_OS
		for (sg = 0; sg < skb_shinfo(skb)->nr_frags; sg++){
			
			skb_frag_t *frag = &skb_shinfo(skb)->frags[sg];
#if (LINUX_VERSION_CODE > KERNEL_VERSION(5, 0, 0))
			memcpy(xmit,page_address(frag->bv_page) + frag->bv_offset,frag->bv_len);
#elif (LINUX_VERSION_CODE < KERNEL_VERSION(3, 2, 0))		
			memcpy(xmit,page_address(frag->page) + frag->page_offset,frag->size);
#else
			memcpy(xmit,page_address(frag->page.p) + frag->page_offset,frag->size);
#endif
#if (LINUX_VERSION_CODE > KERNEL_VERSION(5, 0, 0))
			xmit += frag->bv_len;
			sg_len += frag->bv_len;
#else
			xmit += frag->size;
			sg_len += frag->size;
#endif
		}
#endif
		atbm_dev_kfree_skb(skb);
		return;		
	}

	memcpy(xmit,wsm,xmit_len);
	
	if(skb)
		atbm_dev_kfree_skb(skb);
}

/* privid for wiphys to determine whether they belong to us or not */
void *mac80211_wiphy_privid = &mac80211_wiphy_privid;
u8 *ieee80211_get_bssid(struct ieee80211_hdr *hdr, size_t len,
			enum nl80211_iftype type)
{
	__le16 fc = hdr->frame_control;

	 /* drop ACK/CTS frames and incorrect hdr len (ctrl) */
	if (len < 16)
		return NULL;

	if (ieee80211_is_data(fc)) {
		if (len < 24) /* drop incorrect hdr len (data) */
			return NULL;

		if (ieee80211_has_a4(fc))
			return NULL;
		if (ieee80211_has_tods(fc))
			return hdr->addr1;
		if (ieee80211_has_fromds(fc))
			return hdr->addr2;

		return hdr->addr3;
	}

	if (ieee80211_is_mgmt(fc)) {
		if (len < 24) /* drop incorrect hdr len (mgmt) */
			return NULL;
		return hdr->addr3;
	}

	if (ieee80211_is_ctl(fc)) {
		if(ieee80211_is_pspoll(fc))
			return hdr->addr1;

		if (ieee80211_is_back_req(fc)) {
			switch (type) {
			case NL80211_IFTYPE_STATION:
				return hdr->addr2;
			case NL80211_IFTYPE_AP:
			case NL80211_IFTYPE_AP_VLAN:
				return hdr->addr1;
			default:
				break; /* fall through to the return */
			}
		}
	}

	return NULL;
}

static int ieee802_11_parse_vendor_specific(u8 *pos, size_t elen,
					    struct ieee802_atbm_11_elems *elems,
					    int show_errors)
{
	unsigned int oui;

	/* first 3 bytes in vendor specific information element are the IEEE
	 * OUI of the vendor. The following byte is used a vendor specific
	 * sub-type. */
	if (elen < 4) {
		if (show_errors) {
			atbm_printk_err("short vendor specific "
				   "information element ignored (len=%lu)",
				   (unsigned long) elen);
		}
		return -1;
	}

	oui = ATBM_WPA_GET_BE24(pos);
	switch (oui) {
	case ATBM_OUI_MICROSOFT:
		/* Microsoft/Wi-Fi information elements are further typed and
		 * subtyped */
		switch (pos[3]) {
		case 1:
			/* Microsoft OUI (00:50:F2) with OUI Type 1:
			 * real WPA information element */
			elems->wpa = pos;
			elems->wpa_len = elen;
			break;
		case ATBM_WMM_OUI_TYPE:
			/* WMM information element */
			if (elen < 5) {
				atbm_printk_debug( "short WMM "
					   "information element ignored "
					   "(len=%lu)",
					   (unsigned long) elen);
				return -1;
			}
			switch (pos[4]) {
			case ATBM_WMM_OUI_SUBTYPE_INFORMATION_ELEMENT:
				elems->wmm_info = pos;
				elems->wmm_info_len = elen;
				break;
			case ATBM_WMM_OUI_SUBTYPE_PARAMETER_ELEMENT:
				elems->wmm_param = pos;
				elems->wmm_param_len = elen;
				break;
			default:
				atbm_printk_debug( "unknown WMM "
					   "information element ignored "
					   "(subtype=%d len=%lu)",
					   pos[4], (unsigned long) elen);
				return -1;
			}
			break;
		case 4:
			/* Wi-Fi Protected Setup (WPS) IE */
			elems->wps_ie = pos;
			elems->wps_ie_len = elen;
			break;
		default:
			atbm_printk_debug( "Unknown Microsoft "
				   "information element ignored "
				   "(type=%d len=%lu)",
				   pos[3], (unsigned long) elen);
			return -1;
		}
		break;

	case ATBM_OUI_WFA:
		switch (pos[3]) {
		case ATBM_P2P_OUI_TYPE:
			/* Wi-Fi Alliance - P2P IE */
			elems->p2p_ie = pos;
			elems->p2p_ie_len = elen;
			break;
		case ATBM_WFD_OUI_TYPE:
			/* Wi-Fi Alliance - WFD IE */
			elems->wfd = pos;
			elems->wfd_len = elen;
			break;
		default:
			atbm_printk_debug("Unknown WFA "
				   "information element ignored "
				   "(type=%d len=%lu)\n",
				   pos[3], (unsigned long) elen);
			return -1;
		}
		break;

	default:
		/*
		printk( "unknown vendor specific "
			   "information element ignored (vendor OUI "
			   "%02x:%02x:%02x len=%lu)",
			   pos[0], pos[1], pos[2], (unsigned long) elen);*/
		return -1;
	}

	return 0;
}

u32 atbm_ieee802_11_parse_elems_crc(u8 *start, size_t len,
			       struct ieee802_atbm_11_elems *elems,
			       u64 filter, u32 crc)
{
	size_t left = len;
	u8 *pos = start;
	bool calc_crc = filter != 0;

	memset(elems, 0, sizeof(*elems));
	elems->ie_start = start;
	elems->total_len = len;

	while (left >= 2) {
		u8 id, elen;

		id = *pos++;
		elen = *pos++;
		left -= 2;

		if (elen > left)
			break;

		if (calc_crc && id < 64 && (filter & (1ULL << id)))
			crc = crc32_be(crc, pos - 2, elen + 2);

		switch (id) {
		case ATBM_WLAN_EID_SSID:
			elems->ssid = pos;
			elems->ssid_len = elen;
			break;
		case ATBM_WLAN_EID_SUPP_RATES:
			elems->supp_rates = pos;
			elems->supp_rates_len = elen;
			break;
		case ATBM_WLAN_EID_FH_PARAMS:
			elems->fh_params = pos;
			elems->fh_params_len = elen;
			break;
		case ATBM_WLAN_EID_DS_PARAMS:
			elems->ds_params = pos;
			elems->ds_params_len = elen;
			break;
		case ATBM_WLAN_EID_CF_PARAMS:
			elems->cf_params = pos;
			elems->cf_params_len = elen;
			break;
		case ATBM_WLAN_EID_TIM:
			if (elen >= sizeof(struct ieee80211_tim_ie)) {
				elems->tim = (void *)pos;
				elems->tim_len = elen;
			}
			break;
		case ATBM_WLAN_EID_IBSS_PARAMS:
			elems->ibss_params = pos;
			elems->ibss_params_len = elen;
			break;
		case ATBM_WLAN_EID_CHALLENGE:
			elems->challenge = pos;
			elems->challenge_len = elen;
			break;
		case ATBM_WLAN_EID_VENDOR_SPECIFIC:
			#if 0
			if (elen >= 4 && pos[0] == 0x00 && pos[1] == 0x50 &&
			    pos[2] == 0xf2) {
				/* Microsoft OUI (00:50:F2) */

				if (calc_crc)
					crc = crc32_be(crc, pos - 2, elen + 2);

				if (pos[3] == 1) {
					/* OUI Type 1 - WPA IE */
					elems->wpa = pos;
					elems->wpa_len = elen;
				} else if (elen >= 5 && pos[3] == 2) {
					/* OUI Type 2 - WMM IE */
					if (pos[4] == 0) {
						elems->wmm_info = pos;
						elems->wmm_info_len = elen;
					} else if (pos[4] == 1) {
						elems->wmm_param = pos;
						elems->wmm_param_len = elen;
					}
				}
			}
			/*
			*process p2p ie
			*p2p outui {0x50,0x6F,0x9A,0x09};
			*/
			if(elen >= 4 && pos[0] == 0x50 && pos[1] == 0x6F &&
			    pos[2] == 0x9A && pos[3]== 0x09)
			{
				if (calc_crc)
					crc = crc32_be(crc, pos - 2, elen + 2);
				elems->p2p_ie = pos;
				elems->p2p_ie_len = elen;
			}
			#endif
			ieee802_11_parse_vendor_specific(pos,elen,elems,1);
			break;
		case ATBM_WLAN_EID_RSN:
			elems->rsn = pos;
			elems->rsn_len = elen;
			break;
		case ATBM_WLAN_EID_ERP_INFO:
			elems->erp_info = pos;
			elems->erp_info_len = elen;
			break;
		case ATBM_WLAN_EID_EXT_SUPP_RATES:
			elems->ext_supp_rates = pos;
			elems->ext_supp_rates_len = elen;
			break;
		case ATBM_WLAN_EID_HT_CAPABILITY:
			if (elen >= sizeof(struct ieee80211_ht_cap))
				elems->ht_cap_elem = (void *)pos;
			break;
		case ATBM_WLAN_EID_HT_INFORMATION:
			if (elen >= sizeof(struct ieee80211_ht_info))
				elems->ht_info_elem = (void *)pos;
			break;
		case ATBM_WLAN_EID_MESH_ID:
			elems->mesh_id = pos;
			elems->mesh_id_len = elen;
			break;
		case ATBM_WLAN_EID_MESH_CONFIG:
			if (elen >= sizeof(struct ieee80211_meshconf_ie))
				elems->mesh_config = (void *)pos;
			break;
		case ATBM_WLAN_EID_PEER_MGMT:
			elems->peering = pos;
			elems->peering_len = elen;
			break;
		case ATBM_WLAN_EID_PREQ:
			elems->preq = pos;
			elems->preq_len = elen;
			break;
		case ATBM_WLAN_EID_PREP:
			elems->prep = pos;
			elems->prep_len = elen;
			break;
		case ATBM_WLAN_EID_PERR:
			elems->perr = pos;
			elems->perr_len = elen;
			break;
		case ATBM_WLAN_EID_RANN:
			if (elen >= sizeof(struct ieee80211_rann_ie))
				elems->rann = (void *)pos;
			break;
		case ATBM_WLAN_EID_CHANNEL_SWITCH:
			elems->ch_switch_elem = pos;
			elems->ch_switch_elem_len = elen;
			break;
		case ATBM_WLAN_EID_QUIET:
			if (!elems->quiet_elem) {
				elems->quiet_elem = pos;
				elems->quiet_elem_len = elen;
			}
			elems->num_of_quiet_elem++;
			break;
		case ATBM_WLAN_EID_COUNTRY:
			elems->country_elem = pos;
			elems->country_elem_len = elen;
			break;
		case ATBM_WLAN_EID_PWR_CONSTRAINT:
			elems->pwr_constr_elem = pos;
			elems->pwr_constr_elem_len = elen;
			break;
		case ATBM_WLAN_EID_TIMEOUT_INTERVAL:
			elems->timeout_int = pos;
			elems->timeout_int_len = elen;
			break;
		case ATBM_WLAN_EID_EXT_CHANSWITCH_ANN:
			elems->extended_ch_switch_elem = pos;
			elems->extended_ch_switch_elem_len = elen;
			break;
		case ATBM_WLAN_EID_SECONDARY_CH_OFFSET:
			elems->secondary_ch_elem=pos;
			elems->secondary_ch_elem_len=elen;
		case ATBM_WLAN_EID_PRIVATE:
			elems->atbm_special = pos;
			elems->atbm_special_len = elen;
			break;
		default:
			break;
		}

		left -= elen;
		pos += elen;
	}

	return crc;
}

void ieee802_11_parse_elems(u8 *start, size_t len,
			    struct ieee802_atbm_11_elems *elems)
{
	atbm_ieee802_11_parse_elems_crc(start, len, elems, 0, 0);
}

