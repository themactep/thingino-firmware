/*
 * Copyright 2002-2005, Instant802 Networks, Inc.
 * Copyright 2005, Devicescape Software, Inc.
 * Copyright 2006-2007	Jiri Benc <jbenc@suse.cz>
 * Copyright 2007-2010	Johannes Berg <johannes@sipsolutions.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef IEEE80211_I_H
#define IEEE80211_I_H

#ifdef LINUX_OS
#include <linux/kernel.h>
#include <linux/device.h>
#include <linux/if_ether.h>
#include <linux/interrupt.h>
#include <linux/list.h>
#include <linux/hash.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/workqueue.h>
#include <linux/types.h>
#include <linux/spinlock.h>
#include <linux/etherdevice.h>
#include <linux/leds.h>
#include <net/ieee80211_radiotap.h>
#include <net/cfg80211.h>
#include <net/atbm_mac80211.h>
#endif
#include "sta_info.h"
#include "ieee80211_atbm_mem.h"
#include "ieee80211_atbm_skb.h"

#define ATBM_MICHAEL_MIC_LEN 8
/* OUI's */
#define WIFI_OUI			{0x00, 0x50, 0xF2}
#define WFA_OUI			 {0x50, 0x6F, 0x9A}
#define ATBM_OUI			{0x00, 0xAA, 0xBB}
#define WIFI_WPA_OUI_TYPE	       0x01
#define WIFI_WME_OUI_TYPE	       0x02
#define WIFI_WPS_OUI_TYPE	       0x04
#define WIFI_P2P_IE_OUI_TYPE	    0x09
#define WIFI_ATBM_IE_OUI_TYPE	    0x0a

#define D11_WIFI_ELT_ID		0xDD 

#define wdev_to_ndev(w) ((w)->netdev)
struct ieee80211_local;

/* Maximum number of broadcast/multicast frames to buffer when some of the
 * associated stations are using power saving. */
#define AP_MAX_BC_BUFFER 128

/* Maximum number of frames buffered to all STAs, including multicast frames.
 * Note: increasing this limit increases the potential memory requirement. Each
 * frame can be up to about 2 kB long. */
#define TOTAL_MAX_TX_BUFFER 512

/* Required encryption head and tailroom */
#define IEEE80211_ENCRYPT_HEADROOM 20
#define IEEE80211_ENCRYPT_TAILROOM 18

/* IEEE 802.11 (Ch. 9.5 Defragmentation) requires support for concurrent
 * reception of at least three fragmented frames. This limit can be increased
 * by changing this define, at the cost of slower frame reassembly and
 * increased memory use (about 2 kB of RAM per entry). */
#define IEEE80211_FRAGMENT_MAX 4
#ifndef TU_TO_EXP_TIME
#define TU_TO_EXP_TIME(x)	(jiffies + usecs_to_jiffies((x) * 1024))
#endif

#define IEEE80211_DEFAULT_UAPSD_QUEUES \
	(IEEE80211_WMM_IE_STA_QOSINFO_AC_BK |	\
	 IEEE80211_WMM_IE_STA_QOSINFO_AC_BE |	\
	 IEEE80211_WMM_IE_STA_QOSINFO_AC_VI |	\
	 IEEE80211_WMM_IE_STA_QOSINFO_AC_VO)

#define IEEE80211_DEFAULT_MAX_SP_LEN		\
	IEEE80211_WMM_IE_STA_QOSINFO_SP_ALL
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3, 10, 0))
/**
 * struct ieee80211_ht_info - HT information
 *
 * This structure is the "HT information element" as
 * described in 802.11n D5.0 7.3.2.58
 */
struct ieee80211_ht_info {
	u8 control_chan;
	u8 ht_param;
	__le16 operation_mode;
	__le16 stbc_param;
	u8 basic_set[16];
} __attribute__ ((packed));
#endif
struct ieee80211_fragment_entry {
	unsigned long first_frag_time;
	unsigned int seq;
	unsigned int rx_queue;
	unsigned int last_frag;
	unsigned int extra_len;
	struct sk_buff_head skb_list;
	int ccmp; /* Whether fragments were encrypted with CCMP */
	u8 last_pn[6]; /* PN of the last fragment if CCMP was used */
};

/* Parsed Information Elements */
struct ieee802_atbm_11_elems {
	u8 *ie_start;
	size_t total_len;

	/* pointers to IEs */
	u8 *ssid;
	u8 *supp_rates;
	u8 *fh_params;
	u8 *ds_params;
	u8 *cf_params;
	struct ieee80211_tim_ie *tim;
	u8 *ibss_params;
	u8 *challenge;
	u8 *wpa;
	u8 *rsn;
	u8 *erp_info;
	u8 *ext_supp_rates;
	u8 *wmm_info;
	u8 *wmm_param;
	u8 *p2p_ie;
	const u8 *wfd;
	const u8 *hs20;
	struct ieee80211_ht_cap *ht_cap_elem;
	struct ieee80211_ht_info *ht_info_elem;
	struct ieee80211_meshconf_ie *mesh_config;
	u8 *mesh_id;
	u8 *peering;
	u8 *preq;
	u8 *prep;
	u8 *perr;
	struct ieee80211_rann_ie *rann;
	u8 *ch_switch_elem;
	u8 *country_elem;
	u8 *pwr_constr_elem;
	u8 *quiet_elem;	/* first quite element */
	u8 *timeout_int;
	const u8 *wps_ie;
	u8 *extended_ch_switch_elem;
	u8 * secondary_ch_elem;
	u8 *atbm_special;
	/* length of them, respectively */
	u8 ssid_len;
	u8 supp_rates_len;
	u8 fh_params_len;
	u8 ds_params_len;
	u8 cf_params_len;
	u8 tim_len;
	u8 ibss_params_len;
	u8 challenge_len;
	u8 wpa_len;
	u8 rsn_len;
	u8 erp_info_len;
	u8 ext_supp_rates_len;
	u8 wmm_info_len;
	u8 wmm_param_len;
	u8 p2p_ie_len;
	u8 mesh_id_len;
	u8 peering_len;
	u8 preq_len;
	u8 prep_len;
	u8 perr_len;
	u8 ch_switch_elem_len;
	u8 country_elem_len;
	u8 pwr_constr_elem_len;
	u8 quiet_elem_len;
	u8 num_of_quiet_elem;	/* can be more the one */
	u8 timeout_int_len;
	u8 wfd_len;
	u8 wps_ie_len;	
	u8 extended_ch_switch_elem_len;
	u8 secondary_ch_elem_len;
	u8 atbm_special_len;
};
struct ieee80211_bss {
	/* don't want to look up all the time */
#ifdef SIGMSTAR_SCAN_FEATURE
	s8 noise_floor;
#endif  //SIGMSTAR_SCAN_FEATURE
	size_t ssid_len;
	u8 ssid[IEEE80211_MAX_SSID_LEN];

	u8 dtim_period;

	bool wmm_used;
	bool uapsd_supported;

	unsigned long last_probe_resp;

#ifdef CONFIG_MAC80211_ATBM_MESH
	u8 *mesh_id;
	size_t mesh_id_len;
	u8 *mesh_cfg;
#endif

#define IEEE80211_MAX_SUPP_RATES 32
	u8 supp_rates[IEEE80211_MAX_SUPP_RATES];
	size_t supp_rates_len;

	/*
	 * During association, we save an ERP value from a probe response so
	 * that we can feed ERP info to the driver when handling the
	 * association completes. these fields probably won't be up-to-date
	 * otherwise, you probably don't want to use them.
	 */
	bool has_erp_value;
	u8 erp_value;
};
typedef unsigned __bitwise__ ieee80211_tx_result;
#define TX_CONTINUE	((__force ieee80211_tx_result) 0u)
#define TX_DROP		((__force ieee80211_tx_result) 1u)
#define TX_QUEUED	((__force ieee80211_tx_result) 2u)

#define IEEE80211_TX_UNICAST		BIT(1)
#define IEEE80211_TX_PS_BUFFERED	BIT(2)

struct ieee80211_tx_data {
	struct sk_buff *skb;
	struct ieee80211_local *local;
	struct ieee80211_sub_if_data *sdata;
	struct sta_info *sta;
	struct ieee80211_key *key;

	struct ieee80211_channel *channel;

	u16 ethertype;
	unsigned int flags;
};
struct atbm_wpa_eapol_key {
	u8 type;
	/* Note: key_info, key_length, and key_data_length are unaligned */
	u8 key_info[2]; /* big endian */
	u8 key_length[2]; /* big endian */
	u8 replay_counter[ATBM_WPA_REPLAY_COUNTER_LEN];
	u8 key_nonce[ATBM_WPA_NONCE_LEN];
	u8 key_iv[16];
	u8 key_rsc[ATBM_WPA_KEY_RSC_LEN];
	u8 key_id[8]; /* Reserved in IEEE 802.11i/RSN */
	/* variable length Key MIC field */
	/* big endian 2-octet Key Data Length field */
	/* followed by Key Data Length bytes of Key Data */
} __attribute__ ((packed));

typedef unsigned __bitwise__ ieee80211_rx_result;
#define RX_CONTINUE		((__force ieee80211_rx_result) 0u)
#define RX_DROP_UNUSABLE	((__force ieee80211_rx_result) 1u)
#define RX_DROP_MONITOR		((__force ieee80211_rx_result) 2u)
#define RX_QUEUED		((__force ieee80211_rx_result) 3u)

/**
 * enum ieee80211_packet_rx_flags - packet RX flags
 * @IEEE80211_RX_RA_MATCH: frame is destined to interface currently processed
 *	(incl. multicast frames)
 * @IEEE80211_RX_IN_SCAN: received while scanning
 * @IEEE80211_RX_FRAGMENTED: fragmented frame
 * @IEEE80211_RX_AMSDU: a-MSDU packet
 * @IEEE80211_RX_MALFORMED_ACTION_FRM: action frame is malformed
 * @IEEE80211_RX_DEFERRED_RELEASE: frame was subjected to receive reordering
 *
 * These are per-frame flags that are attached to a frame in the
 * @rx_flags field of &struct ieee80211_rx_status.
 */
enum ieee80211_packet_rx_flags {
	IEEE80211_RX_IN_SCAN			= BIT(0),
	IEEE80211_RX_RA_MATCH			= BIT(1),
	IEEE80211_RX_FRAGMENTED			= BIT(2),
	IEEE80211_RX_AMSDU			= BIT(3),
	IEEE80211_RX_MALFORMED_ACTION_FRM	= BIT(4),
	IEEE80211_RX_DEFERRED_RELEASE		= BIT(5),
	IEEE80211_RX_ERP_BEACON			= BIT(6),
	IEEE80211_RX_SPECIAL_PROBE_REQ  = BIT(7),
};

/**
 * enum ieee80211_rx_flags - RX data flags
 *
 * @IEEE80211_RX_CMNTR: received on cooked monitor already
 *
 * These flags are used across handling multiple interfaces
 * for a single frame.
 */
enum ieee80211_rx_flags {
	IEEE80211_RX_CMNTR		= BIT(0),
};
struct ieee80211_rx_data {
	struct sk_buff *skb;
	struct atbm_common *hw_priv;
	struct atbm_vif *vif;
	struct sta_info *sta;
	struct ieee80211_key *key;
	unsigned int flags;

	/*
	 * Index into sequence numbers array, 0..16
	 * since the last (16) is used for non-QoS,
	 * will be 16 on non-QoS frames.
	 */
	int seqno_idx;

	/*
	 * Index into the security IV/PN arrays, 0..16
	 * since the last (16) is used for CCMP-encrypted
	 * management frames, will be set to 16 on mgmt
	 * frames and 0 on non-QoS frames.
	 */
	int security_idx;

	u32 tkip_iv32;
	u16 tkip_iv16;
};

/* flags used in struct ieee80211_if_managed.flags */
enum ieee80211_sta_flags {
	IEEE80211_STA_BEACON_POLL	= BIT(0),
	IEEE80211_STA_CONNECTION_POLL	= BIT(1),
	IEEE80211_STA_CONTROL_PORT	= BIT(2),
	IEEE80211_STA_DISABLE_11N	= BIT(4),
	IEEE80211_STA_CSA_RECEIVED	= BIT(5),
	IEEE80211_STA_MFP_ENABLED	= BIT(6),
	IEEE80211_STA_UAPSD_ENABLED	= BIT(7),
	IEEE80211_STA_NULLFUNC_ACKED	= BIT(8),
	IEEE80211_STA_RESET_SIGNAL_AVE	= BIT(9),
};
enum sdata_queue_type {
	IEEE80211_SDATA_QUEUE_TYPE_FRAME	= 0,
	IEEE80211_SDATA_QUEUE_AGG_START		= 1,
	IEEE80211_SDATA_QUEUE_AGG_STOP		= 2,
	IEEE80211_SDATA_QUEUE_SEND_STATUS   = 3,
	IEEE80211_SDATA_QUEUE_TIME_OUT		= 4,
	IEEE80211_SDATA_QUEUE_FLUSH			= 5,
};


enum {
	IEEE80211_RX_MSG	= 1,
	IEEE80211_TX_STATUS_MSG	= 2,
	IEEE80211_EOSP_MSG	= 3,
};

enum queue_stop_reason {
	IEEE80211_QUEUE_STOP_REASON_DRIVER,
	IEEE80211_QUEUE_STOP_REASON_PS,
	IEEE80211_QUEUE_STOP_REASON_CSA,
	IEEE80211_QUEUE_STOP_REASON_AGGREGATION,
	IEEE80211_QUEUE_STOP_REASON_SUSPEND,
	IEEE80211_QUEUE_STOP_REASON_SKB_ADD,
	IEEE80211_QUEUE_STOP_REASON_CHTYPE_CHANGE,
};


/**
 * mac80211 scan flags - currently active scan mode
 *
 * @SCAN_SW_SCANNING: We're currently in the process of scanning but may as
 *	well be on the operating channel
 * @SCAN_HW_SCANNING: The hardware is scanning for us, we have no way to
 *	determine if we are on the operating channel or not
 * @SCAN_OFF_CHANNEL: We're off our operating channel for scanning,
 *	gets only set in conjunction with SCAN_SW_SCANNING
 * @SCAN_COMPLETED: Set for our scan work function when the driver reported
 *	that the scan completed.
 * @SCAN_ABORTED: Set for our scan work function when the driver reported
 *	a scan complete for an aborted scan.
 */
enum {
	SCAN_SW_SCANNING,
	SCAN_HW_SCANNING,
	SCAN_OFF_CHANNEL,
	SCAN_COMPLETED,
	SCAN_ABORTED,
	SCAN_INTERNAL_SCANNING,
	SCAN_CFG80211_SCANNING,
};

void ieee80211_process_addba_request(struct atbm_common *hw_priv,
				     struct sta_info *sta,
				     struct atbm_ieee80211_mgmt *mgmt,
				     size_t len);
void ieee80211_sta_tear_down_BA_sessions(struct sta_info *sta, bool tx);
void ___ieee80211_stop_rx_ba_session(struct sta_info *sta, u16 tid,
				     u16 initiator, u16 reason, bool tx);
void __ieee80211_stop_rx_ba_session(struct sta_info *sta, u16 tid,
				    u16 initiator, u16 reason, bool tx);
void ieee80211_process_delba(struct atbm_vif *vif,
			     struct sta_info *sta,
			     struct atbm_ieee80211_mgmt *mgmt, size_t len);

void ieee80211_release_reorder_timeout(struct sta_info *sta, int tid);
void ieee80211_rx(struct atbm_vif *vif, struct sk_buff *skb);
u8 *ieee80211_get_bssid(struct ieee80211_hdr *hdr, size_t len,
			enum nl80211_iftype type);
void ieee80211_ba_session_work(struct work_struct *work);

#endif /* IEEE80211_I_H */
