/*
 * mac80211 <-> driver interface
 *
 * Copyright 2002-2005, Devicescape Software, Inc.
 * Copyright 2006-2007	Jiri Benc <jbenc@suse.cz>
 * Copyright 2007-2010	Johannes Berg <johannes@sipsolutions.net>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef ATBM_MAC80211_H
#define ATBM_MAC80211_H

#include <linux/kernel.h>
#include <linux/if_ether.h>
#include <linux/skbuff.h>
#include <linux/device.h>
#include <linux/ieee80211.h>
#include <net/cfg80211.h>
#include <asm/unaligned.h>
#include <linux/hash.h>

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 7, 0))
#define IEEE80211_BAND_2GHZ NL80211_BAND_2GHZ
#define IEEE80211_BAND_5GHZ NL80211_BAND_5GHZ
#define IEEE80211_NUM_BANDS (NL80211_BAND_5GHZ+1)
#define ieee80211_band nl80211_band 
#define atbm_notify_scan_done(__local,__scan_request,__abort) \
do	{			\
	__local->scan_info.aborted = __abort;		\
	cfg80211_scan_done(__scan_request,&__local->scan_info);		\
}while(0)
#else
struct cfg80211_scan_info{
	bool aborted;
};
#define atbm_notify_scan_done(__local,__scan_request,__abort) \
do {			\
	BUG_ON(__local==NULL);			\
	cfg80211_scan_done(__scan_request,__abort);				\
}while(0)
#endif

#ifdef IPV6_FILTERING
#include <linux/in6.h>
#endif /*IPV6_FILTERING*/

#ifndef IEEE80211_QOS_CTL_EOSP
#define IEEE80211_QOS_CTL_EOSP			0x0010
#endif

#ifndef IEEE80211_BAR_CTRL_MULTI_TID
#define IEEE80211_BAR_CTRL_MULTI_TID		0x0002
#endif
#ifndef IEEE80211_BAR_CTRL_TID_INFO_MASK
#define IEEE80211_BAR_CTRL_TID_INFO_MASK	0xf000
#endif

#ifndef IEEE80211_BAR_CTRL_TID_INFO_SHIFT
#define IEEE80211_BAR_CTRL_TID_INFO_SHIFT	12
#endif
#if (LINUX_VERSION_CODE < KERNEL_VERSION(4, 19, 0))
#ifndef IEEE80211_RADIOTAP_F_TX_NOACK
#define IEEE80211_RADIOTAP_F_TX_NOACK	0x0008	/* don't expect an ack */
#endif
#endif
#ifndef IEEE80211_QOS_CTL_ACK_POLICY_NOACK
#define IEEE80211_QOS_CTL_ACK_POLICY_NOACK	0x0020
#endif

#ifndef IEEE80211_QOS_CTL_MESH_CONTROL_PRESENT
#define IEEE80211_QOS_CTL_MESH_CONTROL_PRESENT  0x0100
#endif

#ifndef ERP_INFO_BYTE_OFFSET
#define ERP_INFO_BYTE_OFFSET 2
#endif

static inline unsigned atbm_compare_ether_addr(const u8 *addr1, const u8 *addr2)
{
	const u16 *a = (const u16 *) addr1;
	const u16 *b = (const u16 *) addr2;

	BUILD_BUG_ON(ETH_ALEN != 6);
	return ((a[0] ^ b[0]) | (a[1] ^ b[1]) | (a[2] ^ b[2])) != 0;
}
/* Information Element IDs */
enum atbm_ieee80211_eid {
	ATBM_WLAN_EID_SSID = 0,
	ATBM_WLAN_EID_SUPP_RATES = 1,
	ATBM_WLAN_EID_FH_PARAMS = 2,
	ATBM_WLAN_EID_DS_PARAMS = 3,
	ATBM_WLAN_EID_CF_PARAMS = 4,
	ATBM_WLAN_EID_TIM = 5,
	ATBM_WLAN_EID_IBSS_PARAMS = 6,
	ATBM_WLAN_EID_CHALLENGE = 16,

	ATBM_WLAN_EID_COUNTRY = 7,
	ATBM_WLAN_EID_HP_PARAMS = 8,
	ATBM_WLAN_EID_HP_TABLE = 9,
	ATBM_WLAN_EID_REQUEST = 10,

	ATBM_WLAN_EID_QBSS_LOAD = 11,
	ATBM_WLAN_EID_EDCA_PARAM_SET = 12,
	ATBM_WLAN_EID_TSPEC = 13,
	ATBM_WLAN_EID_TCLAS = 14,
	ATBM_WLAN_EID_SCHEDULE = 15,
	ATBM_WLAN_EID_TS_DELAY = 43,
	ATBM_WLAN_EID_TCLAS_PROCESSING = 44,
	ATBM_WLAN_EID_QOS_CAPA = 46,
	/* 802.11z */
	ATBM_WLAN_EID_LINK_ID = 101,
	/* 802.11s */
	ATBM_WLAN_EID_MESH_CONFIG = 113,
	ATBM_WLAN_EID_MESH_ID = 114,
	ATBM_WLAN_EID_LINK_METRIC_REPORT = 115,
	ATBM_WLAN_EID_CONGESTION_NOTIFICATION = 116,
	ATBM_WLAN_EID_PEER_MGMT = 117,
	ATBM_WLAN_EID_CHAN_SWITCH_PARAM = 118,
	ATBM_WLAN_EID_MESH_AWAKE_WINDOW = 119,
	ATBM_WLAN_EID_BEACON_TIMING = 120,
	ATBM_WLAN_EID_MCCAOP_SETUP_REQ = 121,
	ATBM_WLAN_EID_MCCAOP_SETUP_RESP = 122,
	ATBM_WLAN_EID_MCCAOP_ADVERT = 123,
	ATBM_WLAN_EID_MCCAOP_TEARDOWN = 124,
	ATBM_WLAN_EID_GANN = 125,
	ATBM_WLAN_EID_RANN = 126,
	ATBM_WLAN_EID_PREQ = 130,
	ATBM_WLAN_EID_PREP = 131,
	ATBM_WLAN_EID_PERR = 132,
	ATBM_WLAN_EID_PXU = 137,
	ATBM_WLAN_EID_PXUC = 138,
	ATBM_WLAN_EID_AUTH_MESH_PEER_EXCH = 139,
	ATBM_WLAN_EID_MIC = 140,

	ATBM_WLAN_EID_PWR_CONSTRAINT = 32,
	ATBM_WLAN_EID_PWR_CAPABILITY = 33,
	ATBM_WLAN_EID_TPC_REQUEST = 34,
	ATBM_WLAN_EID_TPC_REPORT = 35,
	ATBM_WLAN_EID_SUPPORTED_CHANNELS = 36,
	ATBM_WLAN_EID_CHANNEL_SWITCH = 37,
	ATBM_WLAN_EID_MEASURE_REQUEST = 38,
	ATBM_WLAN_EID_MEASURE_REPORT = 39,
	ATBM_WLAN_EID_QUIET = 40,
	ATBM_WLAN_EID_IBSS_DFS = 41,

	ATBM_WLAN_EID_ERP_INFO = 42,
	ATBM_WLAN_EID_EXT_SUPP_RATES = 50,

	ATBM_WLAN_EID_HT_CAPABILITY = 45,
	ATBM_WLAN_EID_HT_INFORMATION = 61,

	ATBM_WLAN_EID_RSN = 48,
	ATBM_WLAN_EID_MMIE = 76,
	ATBM_WLAN_EID_WPA = 221,
	ATBM_WLAN_EID_GENERIC = 221,
	ATBM_WLAN_EID_VENDOR_SPECIFIC = 221,
	ATBM_WLAN_EID_QOS_PARAMETER = 222,

	ATBM_WLAN_EID_AP_CHAN_REPORT = 51,
	ATBM_WLAN_EID_NEIGHBOR_REPORT = 52,
	ATBM_WLAN_EID_RCPI = 53,
	ATBM_WLAN_EID_BSS_AVG_ACCESS_DELAY = 63,
	ATBM_WLAN_EID_ANTENNA_INFO = 64,
	ATBM_WLAN_EID_RSNI = 65,
	ATBM_WLAN_EID_MEASUREMENT_PILOT_TX_INFO = 66,
	ATBM_WLAN_EID_BSS_AVAILABLE_CAPACITY = 67,
	ATBM_WLAN_EID_BSS_AC_ACCESS_DELAY = 68,
	ATBM_WLAN_EID_RRM_ENABLED_CAPABILITIES = 70,
	ATBM_WLAN_EID_MULTIPLE_BSSID = 71,
	ATBM_WLAN_EID_BSS_COEX_2040 = 72,
	ATBM_WLAN_EID_OVERLAP_BSS_SCAN_PARAM = 74,
	ATBM_WLAN_EID_EXT_CAPABILITY = 127,

	ATBM_WLAN_EID_MOBILITY_DOMAIN = 54,
	ATBM_WLAN_EID_FAST_BSS_TRANSITION = 55,
	ATBM_WLAN_EID_TIMEOUT_INTERVAL = 56,
	ATBM_WLAN_EID_RIC_DATA = 57,
	ATBM_WLAN_EID_RIC_DESCRIPTOR = 75,

	ATBM_WLAN_EID_DSE_REGISTERED_LOCATION = 58,
	ATBM_WLAN_EID_SUPPORTED_REGULATORY_CLASSES = 59,
	ATBM_WLAN_EID_EXT_CHANSWITCH_ANN = 60,
	ATBM_WLAN_EID_SECONDARY_CH_OFFSET = 62,
	ATBM_WLAN_EID_PRIVATE = 233,
};

struct atbm_wpa_ie_data {
	int proto;
	int pairwise_cipher;
	int group_cipher;
	int key_mgmt;
	int wpa_capabilities;
	int rsn_capabilities;
	size_t num_pmkid;
	const u8 *pmkid;
	int mgmt_group_cipher;
};
#define ATBM_WLAN_CAPABILITY_ESS BIT(0)
#define ATBM_WLAN_CAPABILITY_IBSS BIT(1)
#define ATBM_WLAN_CAPABILITY_CF_POLLABLE BIT(2)
#define ATBM_WLAN_CAPABILITY_CF_POLL_REQUEST BIT(3)
#define ATBM_WLAN_CAPABILITY_PRIVACY BIT(4)
#define ATBM_WLAN_CAPABILITY_SHORT_PREAMBLE BIT(5)
#define ATBM_WLAN_CAPABILITY_PBCC BIT(6)
#define ATBM_WLAN_CAPABILITY_CHANNEL_AGILITY BIT(7)
#define ATBM_WLAN_CAPABILITY_SPECTRUM_MGMT BIT(8)
#define ATBM_WLAN_CAPABILITY_SHORT_SLOT_TIME BIT(10)
#define ATBM_WLAN_CAPABILITY_DSSS_OFDM BIT(13)

/* IEEE 802.11, 7.3.2.25.3 RSN Capabilities */
#define ATBM_WPA_CAPABILITY_PREAUTH BIT(0)
#define ATBM_WPA_CAPABILITY_NO_PAIRWISE BIT(1)
/* B2-B3: PTKSA Replay Counter */
/* B4-B5: GTKSA Replay Counter */
#define ATBM_WPA_CAPABILITY_MFPR BIT(6)
#define ATBM_WPA_CAPABILITY_MFPC BIT(7)
/* B8: Reserved */
#define ATBM_WPA_CAPABILITY_PEERKEY_ENABLED BIT(9)
#define ATBM_WPA_CAPABILITY_SPP_A_MSDU_CAPABLE BIT(10)
#define ATBM_WPA_CAPABILITY_SPP_A_MSDU_REQUIRED BIT(11)
#define ATBM_WPA_CAPABILITY_PBAC BIT(12)
#define ATBM_WPA_CAPABILITY_EXT_KEY_ID_FOR_UNICAST BIT(13)

#define ATBM_WPA_PROTO_WPA BIT(0)
#define ATBM_WPA_PROTO_RSN BIT(1)
#define ATBM_WPA_PROTO_WAPI BIT(2)

#define ATBM_WPA_CIPHER_NONE BIT(0)
#define ATBM_WPA_CIPHER_WEP40 BIT(1)
#define ATBM_WPA_CIPHER_WEP104 BIT(2)
#define ATBM_WPA_CIPHER_TKIP BIT(3)
#define ATBM_WPA_CIPHER_CCMP BIT(4)
#define ATBM_WPA_CIPHER_AES_128_CMAC BIT(5)
#define ATBM_WPA_CIPHER_GCMP BIT(6)
#define ATBM_WPA_CIPHER_SMS4 BIT(7)


#define ATBM_WPA_KEY_MGMT_IEEE8021X BIT(0)
#define ATBM_WPA_KEY_MGMT_PSK BIT(1)
#define ATBM_WPA_KEY_MGMT_NONE BIT(2)
#define ATBM_WPA_KEY_MGMT_IEEE8021X_NO_WPA BIT(3)
#define ATBM_WPA_KEY_MGMT_WPA_NONE BIT(4)
#define ATBM_WPA_KEY_MGMT_FT_IEEE8021X BIT(5)
#define ATBM_WPA_KEY_MGMT_FT_PSK BIT(6)
#define ATBM_WPA_KEY_MGMT_IEEE8021X_SHA256 BIT(7)
#define ATBM_WPA_KEY_MGMT_PSK_SHA256 BIT(8)
#define ATBM_WPA_KEY_MGMT_WPS BIT(9)
#define ATBM_WPA_KEY_MGMT_SAE BIT(10)
#define ATBM_WPA_KEY_MGMT_FT_SAE BIT(11)
#define ATBM_WPA_KEY_MGMT_WAPI_PSK BIT(12)
#define ATBM_WPA_KEY_MGMT_WAPI_CERT BIT(13)
#define ATBM_WPA_KEY_MGMT_CCKM BIT(14)

#define ATBM_OUI_MICROSOFT 0x0050f2 /* Microsoft (also used in Wi-Fi specs)*/
#define ATBM_WMM_OUI_TYPE  2
#define ATBM_WMM_OUI_SUBTYPE_INFORMATION_ELEMENT 0
#define ATBM_WMM_OUI_SUBTYPE_PARAMETER_ELEMENT 1
#define ATBM_WMM_OUI_SUBTYPE_TSPEC_ELEMENT 2

#define ATBM_OUI_WFA 0x506f9a
#define ATBM_P2P_IE_VENDOR_TYPE 0x506f9a09
#define ATBM_WFD_IE_VENDOR_TYPE 0x506f9a0a
#define ATBM_WFD_OUI_TYPE 10
#define ATBM_HS20_IE_VENDOR_TYPE 0x506f9a10
#define ATBM_HS20_INDICATION_OUI_TYPE 16

#define ATBM_P2P_OUI_TYPE 9
#define ATBM_OUI_BROADCOM 0x00904c /* Broadcom (Epigram) */

#define ATBM_WPA_SELECTOR_LEN 4
#define ATBM_WPA_VERSION 1
#define ATBM_RSN_SELECTOR_LEN 4
#define ATBM_RSN_VERSION 1

static inline u32 ATBM_WPA_GET_BE24(const u8 *a)
{
	return (a[0] << 16) | (a[1] << 8) | a[2];
}

static inline u32 ATBM_WPA_GET_BE32(const u8 *a)
{
	return (a[0] << 24) | (a[1] << 16) | (a[2] << 8) | a[3];
}

static inline u16 ATBM_WPA_GET_LE16(const u8 *a)
{
	return (a[1] << 8) | a[0];
}

#define ATBM_RSN_CIPHER_SUITE_NONE 					0x000fac00
#define ATBM_RSN_CIPHER_SUITE_WEP40					0x000fac01
#define ATBM_RSN_CIPHER_SUITE_TKIP 					0x000fac02
#define ATBM_RSN_CIPHER_SUITE_CCMP 					0x000fac04
#define ATBM_RSN_CIPHER_SUITE_WEP104 				0x000fac05
#define ATBM_RSN_CIPHER_SUITE_AES_128_CMAC 			0x000fac06
#define ATBM_RSN_CIPHER_SUITE_NO_GROUP_ADDRESSED 	0x000fac07
#define ATBM_RSN_CIPHER_SUITE_GCMP 					0x000fac08


#define ATBM_RSN_AUTH_KEY_MGMT_UNSPEC_802_1X 		0x000fac01
#define ATBM_RSN_AUTH_KEY_MGMT_PSK_OVER_802_1X 		0x000fac02
#define ATBM_RSN_AUTH_KEY_MGMT_FT_802_1X 			0x000fac03
#define ATBM_RSN_AUTH_KEY_MGMT_FT_PSK 				0x000fac04
#define ATBM_RSN_AUTH_KEY_MGMT_802_1X_SHA256 		0x000fac05
#define ATBM_RSN_AUTH_KEY_MGMT_PSK_SHA256 			0x000fac06
#define ATBM_RSN_AUTH_KEY_MGMT_TPK_HANDSHAKE 		0x000fac07
#define ATBM_RSN_AUTH_KEY_MGMT_SAE 					0x000fac08
#define ATBM_RSN_AUTH_KEY_MGMT_FT_SAE				0x000fac09
#define ATBM_RSN_AUTH_KEY_MGMT_CCKM 				0x00409600

/* AKM suite selectors */
#define ATBM_WLAN_AKM_SUITE_8021X					0x000FAC01
#define ATBM_WLAN_AKM_SUITE_PSK						0x000FAC02
#define ATBM_WLAN_AKM_SUITE_8021X_SHA256			0x000FAC05
#define ATBM_WLAN_AKM_SUITE_PSK_SHA256				0x000FAC06
#define ATBM_WLAN_AKM_SUITE_TDLS					0x000FAC07
#define ATBM_WLAN_AKM_SUITE_SAE						0x000FAC08
#define ATBM_WLAN_AKM_SUITE_FT_OVER_SAE				0x000FAC09
#define ATBM_WLAN_AKM_SUITE_802_1X_SUITE_B_192 		0x000fac12
#define ATBM_WLAN_AKM_SUITE_FILS_SHA256 			0x000fac14
#define ATBM_WLAN_AKM_SUITE_FILS_SHA384 			0x000fac15
#define ATBM_WLAN_AKM_SUITE_FT_FILS_SHA256 			0x000fac16
#define ATBM_WLAN_AKM_SUITE_FT_FILS_SHA384 			0x000fac17

#define ATBM_PMKID_LEN 16
#define ATBM_PMK_LEN 32
#define ATBM_WPA_REPLAY_COUNTER_LEN 8
#define ATBM_WPA_NONCE_LEN 32
#define ATBM_WPA_KEY_RSC_LEN 8
#define ATBM_WPA_GMK_LEN 32
#define ATBM_WPA_GTK_MAX_LEN 32


#define ATBM_WPA_AUTH_KEY_MGMT_NONE 				0x0050f200
#define ATBM_WPA_AUTH_KEY_MGMT_UNSPEC_802_1X 		0x0050f201
#define ATBM_WPA_AUTH_KEY_MGMT_PSK_OVER_802_1X 		0x0050f202
#define ATBM_WPA_AUTH_KEY_MGMT_CCKM 				0x00409600
#define ATBM_WPA_CIPHER_SUITE_NONE 					0x0050f200
#define ATBM_WPA_CIPHER_SUITE_WEP40 				0x0050f201
#define ATBM_WPA_CIPHER_SUITE_TKIP 					0x0050f202
#define ATBM_WPA_CIPHER_SUITE_CCMP 					0x0050f204
#define ATBM_WPA_CIPHER_SUITE_WEP104 				0x0050f205

#define ATBM_PRIVATE_OUI							0x4154424D
enum atbm_p2p_attr_id {
	ATBM_P2P_ATTR_STATUS = 0,
	ATBM_P2P_ATTR_MINOR_REASON_CODE = 1,
	ATBM_P2P_ATTR_CAPABILITY = 2,
	ATBM_P2P_ATTR_DEVICE_ID = 3,
	ATBM_P2P_ATTR_GROUP_OWNER_INTENT = 4,
	ATBM_P2P_ATTR_CONFIGURATION_TIMEOUT = 5,
	ATBM_P2P_ATTR_LISTEN_CHANNEL = 6,
	ATBM_P2P_ATTR_GROUP_BSSID = 7,
	ATBM_P2P_ATTR_EXT_LISTEN_TIMING = 8,
	ATBM_P2P_ATTR_INTENDED_INTERFACE_ADDR = 9,
	ATBM_P2P_ATTR_MANAGEABILITY = 10,
	ATBM_P2P_ATTR_CHANNEL_LIST = 11,
	ATBM_P2P_ATTR_NOTICE_OF_ABSENCE = 12,
	ATBM_P2P_ATTR_DEVICE_INFO = 13,
	ATBM_P2P_ATTR_GROUP_INFO = 14,
	ATBM_P2P_ATTR_GROUP_ID = 15,
	ATBM_P2P_ATTR_INTERFACE = 16,
	ATBM_P2P_ATTR_OPERATING_CHANNEL = 17,
	ATBM_P2P_ATTR_INVITATION_FLAGS = 18,
	ATBM_P2P_ATTR_VENDOR_SPECIFIC = 221
};

/* P2P public action frames */
enum atbm_p2p_action_frame_type {
	ATBM_P2P_GO_NEG_REQ = 0,
	ATBM_P2P_GO_NEG_RESP = 1,
	ATBM_P2P_GO_NEG_CONF = 2,
	ATBM_P2P_INVITATION_REQ = 3,
	ATBM_P2P_INVITATION_RESP = 4,
	ATBM_P2P_DEV_DISC_REQ = 5,
	ATBM_P2P_DEV_DISC_RESP = 6,
	ATBM_P2P_PROV_DISC_REQ = 7,
	ATBM_P2P_PROV_DISC_RESP = 8
};
struct atbm_p2p_message {
	u8 dialog_token;

	u8 *capability;
	u8 *go_intent;
	u8 *status;
	u8 *operating_channel;
	u8 *channel_list;
	u8 channel_list_len;
	
	u8 *group_bssid;
	u8 *invitation_flags;

	u8 *group_info;
	size_t group_info_len;

	u8 *group_id;
	size_t group_id_len;

	u8 *device_id;

	u8 *manageability;
	u8 *intended_addr;
};

struct atbm_ieee80211_vendor_ie {
	u8 element_id;
	u8 len;
	u8 oui[3];
	u8 oui_type;
} __packed;

struct atbm_ieee80211_mgmt {
	__le16 frame_control;
	__le16 duration;
	u8 da[6];
	u8 sa[6];
	u8 bssid[6];
	__le16 seq_ctrl;
	union {
		struct {
			__le16 auth_alg;
			__le16 auth_transaction;
			__le16 status_code;
			/* possibly followed by Challenge text */
			u8 variable[0];
		} __attribute__ ((packed)) auth;
		struct {
			__le16 reason_code;
		} __attribute__ ((packed)) deauth;
		struct {
			__le16 capab_info;
			__le16 listen_interval;
			/* followed by SSID and Supported rates */
			u8 variable[0];
		} __attribute__ ((packed)) assoc_req;
		struct {
			__le16 capab_info;
			__le16 status_code;
			__le16 aid;
			/* followed by Supported rates */
			u8 variable[0];
		} __attribute__ ((packed)) assoc_resp, reassoc_resp;
		struct {
			__le16 capab_info;
			__le16 listen_interval;
			u8 current_ap[6];
			/* followed by SSID and Supported rates */
			u8 variable[0];
		} __attribute__ ((packed)) reassoc_req;
		struct {
			__le16 reason_code;
		} __attribute__ ((packed)) disassoc;
		struct {
			__le64 timestamp;
			__le16 beacon_int;
			__le16 capab_info;
			/* followed by some of SSID, Supported rates,
			 * FH Params, DS Params, CF Params, IBSS Params, TIM */
			u8 variable[0];
		} __attribute__ ((packed)) beacon;
		struct {
			/* only variable items: SSID, Supported rates */
			u8 variable[0];
		} __attribute__ ((packed)) probe_req;
		struct {
			__le64 timestamp;
			__le16 beacon_int;
			__le16 capab_info;
			/* followed by some of SSID, Supported rates,
			 * FH Params, DS Params, CF Params, IBSS Params */
			u8 variable[0];
		} __attribute__ ((packed)) probe_resp;
		struct {
			u8 category;
			union {
				struct {
					u8 action; /* 9 */
					u8 oui[3];
					/* Vendor-specific content */
					u8 variable[0];
				}  __attribute__ ((packed)) vs_public_action;
				struct {
					u8 action_code;
					u8 dialog_token;
					u8 status_code;
					u8 variable[0];
				} __attribute__ ((packed)) wme_action;
				struct{
					u8 action_code;
					u8 dialog_token;
					__le16 capab;
					__le16 timeout;
					__le16 start_seq_num;
				} __attribute__((packed)) addba_req;
				struct{
					u8 action_code;
					u8 dialog_token;
					__le16 status;
					__le16 capab;
					__le16 timeout;
				} __attribute__((packed)) addba_resp;
				struct{
					u8 action_code;
					__le16 params;
					__le16 reason_code;
				} __attribute__((packed)) delba;
				struct {
					u8 action_code;
					u8 variable[0];
				} __attribute__((packed)) self_prot;
				struct{
					u8 action_code;
					u8 variable[0];
				} __attribute__((packed)) mesh_action;
				struct {
					u8 action;
					u8 trans_id[WLAN_SA_QUERY_TR_ID_LEN];
				} __attribute__ ((packed)) sa_query;
				struct {
					u8 action;
					u8 smps_control;
				} __attribute__ ((packed)) ht_smps;
				struct {
					u8 action_code;
					u8 dialog_token;
					__le16 capability;
					u8 variable[0];
				} __packed tdls_discover_resp;
			} u;
		} __attribute__ ((packed)) action;
	} u;
} __attribute__ ((packed));


#ifndef WLAN_EXT_CAPA5_TDLS_ENABLED
#define WLAN_EXT_CAPA5_TDLS_ENABLED	BIT(5)
#endif
#ifndef WLAN_TDLS_SNAP_RFTYPE
#define WLAN_TDLS_SNAP_RFTYPE	 0x2
#endif
/**
 * DOC: Introduction
 *
 * mac80211 is the Linux stack for 802.11 hardware that implements
 * only partial functionality in hard- or firmware. This document
 * defines the interface between mac80211 and low-level hardware
 * drivers.
 */

/**
 * DOC: Calling mac80211 from interrupts
 *
 * Only ieee80211_tx_status_irqsafe() and ieee80211_rx_irqsafe() can be
 * called in hardware interrupt context. The low-level driver must not call any
 * other functions in hardware interrupt context. If there is a need for such
 * call, the low-level driver should first ACK the interrupt and perform the
 * IEEE 802.11 code call after this, e.g. from a scheduled workqueue or even
 * tasklet function.
 *
 * NOTE: If the driver opts to use the _irqsafe() functions, it may not also
 *	 use the non-IRQ-safe functions!
 */

/**
 * DOC: Warning
 *
 * If you're reading this document and not the header file itself, it will
 * be incomplete because not all documentation has been converted yet.
 */

/**
 * DOC: Frame format
 *
 * As a general rule, when frames are passed between mac80211 and the driver,
 * they start with the IEEE 802.11 header and include the same octets that are
 * sent over the air except for the FCS which should be calculated by the
 * hardware.
 *
 * There are, however, various exceptions to this rule for advanced features:
 *
 * The first exception is for hardware encryption and decryption offload
 * where the IV/ICV may or may not be generated in hardware.
 *
 * Secondly, when the hardware handles fragmentation, the frame handed to
 * the driver from mac80211 is the MSDU, not the MPDU.
 *
 * Finally, for received frames, the driver is able to indicate that it has
 * filled a radiotap header and put that in front of the frame; if it does
 * not do so then mac80211 may add this under certain circumstances.
 */

/**
 * DOC: mac80211 workqueue
 *
 * mac80211 provides its own workqueue for drivers and internal mac80211 use.
 * The workqueue is a single threaded workqueue and can only be accessed by
 * helpers for sanity checking. Drivers must ensure all work added onto the
 * mac80211 workqueue should be cancelled on the driver stop() callback.
 *
 * mac80211 will flushed the workqueue upon interface removal and during
 * suspend.
 *
 * All work performed on the mac80211 workqueue must not acquire the RTNL lock.
 *
 */

/**
 * enum ieee80211_max_queues - maximum number of queues
 *
 * @IEEE80211_MAX_QUEUES: Maximum number of regular device queues.
 */
enum ieee80211_max_queues {
	IEEE80211_MAX_QUEUES =		16,
};

#define IEEE80211_INVAL_HW_QUEUE	0xff

/**
 * enum ieee80211_ac_numbers - AC numbers as used in mac80211
 * @IEEE80211_AC_VO: voice
 * @IEEE80211_AC_VI: video
 * @IEEE80211_AC_BE: best effort
 * @IEEE80211_AC_BK: background
 */
enum ieee80211_ac_numbers {
	IEEE80211_AC_VO		= 0,
	IEEE80211_AC_VI		= 1,
	IEEE80211_AC_BE		= 2,
	IEEE80211_AC_BK		= 3,
};

/**
 * enum atbmwifi_ieee80211_ac_numbers - AC numbers as used in mac80211
 * @IEEE80211_AC_VO: voice
 * @IEEE80211_AC_VI: video
 * @IEEE80211_AC_BE: best effort
 * @IEEE80211_AC_BK: background
 */
enum atbmwifi_ieee80211_ac_numbers {
	ATBM_IEEE80211_AC_VO		= 0,
	ATBM_IEEE80211_AC_VI		= 1,
	ATBM_IEEE80211_AC_BE		= 2,
	ATBM_IEEE80211_AC_BK		= 3,
};

#define IEEE80211_NUM_ACS	4

/**
 * struct ieee80211_tx_queue_params - transmit queue configuration
 *
 * The information provided in this structure is required for QoS
 * transmit queue configuration. Cf. IEEE 802.11 7.3.2.29.
 *
 * @aifs: arbitration interframe space [0..255]
 * @cw_min: minimum contention window [a value of the form
 *	2^n-1 in the range 1..32767]
 * @cw_max: maximum contention window [like @cw_min]
 * @txop: maximum burst time in units of 32 usecs, 0 meaning disabled
 * @uapsd: is U-APSD mode enabled for the queue
 */
struct ieee80211_tx_queue_params {
	u16 txop;
	u16 cw_min;
	u16 cw_max;
	u8 aifs;
	bool uapsd;
};

struct ieee80211_low_level_stats {
	unsigned int dot11ACKFailureCount;
	unsigned int dot11RTSFailureCount;
	unsigned int dot11FCSErrorCount;
	unsigned int dot11RTSSuccessCount;
};

/**
 * enum ieee80211_bss_change - BSS change notification flags
 *
 * These flags are used with the bss_info_changed() callback
 * to indicate which BSS parameter changed.
 *
 * @BSS_CHANGED_ASSOC: association status changed (associated/disassociated),
 *	also implies a change in the AID.
 * @BSS_CHANGED_ERP_CTS_PROT: CTS protection changed
 * @BSS_CHANGED_ERP_PREAMBLE: preamble changed
 * @BSS_CHANGED_ERP_SLOT: slot timing changed
 * @BSS_CHANGED_HT: 802.11n parameters changed
 * @BSS_CHANGED_BASIC_RATES: Basic rateset changed
 * @BSS_CHANGED_BEACON_INT: Beacon interval changed
 * @BSS_CHANGED_BSSID: BSSID changed, for whatever
 *	reason (IBSS and managed mode)
 * @BSS_CHANGED_BEACON: Beacon data changed, retrieve
 *	new beacon (beaconing modes)
 * @BSS_CHANGED_BEACON_ENABLED: Beaconing should be
 *	enabled/disabled (beaconing modes)
 * @BSS_CHANGED_CQM: Connection quality monitor config changed
 * @BSS_CHANGED_IBSS: IBSS join status changed
 * @BSS_CHANGED_ARP_FILTER: Hardware ARP filter address list or state changed.
 * @BSS_CHANGED_QOS: QoS for this association was enabled/disabled. Note
 *	that it is only ever disabled for station mode.
 * @BSS_CHANGED_IDLE: Idle changed for this BSS/interface.
 * @BSS_CHANGED_SSID: SSID changed for this BSS (AP mode)
 * @BSS_CHANGED_PS: the PS flag or dynamic PS timeout changed
 * @BSS_CHANGED_CHANNEL: vif channel changed
 * @BSS_CHANGED_P2P_PS: NOA parameters changed.
 */
enum ieee80211_bss_change {
	BSS_CHANGED_ASSOC		= 1<<0,
	BSS_CHANGED_ERP_CTS_PROT	= 1<<1,
	BSS_CHANGED_ERP_PREAMBLE	= 1<<2,
	BSS_CHANGED_ERP_SLOT		= 1<<3,
	BSS_CHANGED_HT			= 1<<4,
	BSS_CHANGED_BASIC_RATES		= 1<<5,
	BSS_CHANGED_BEACON_INT		= 1<<6,
	BSS_CHANGED_BSSID		= 1<<7,
	BSS_CHANGED_BEACON		= 1<<8,
	BSS_CHANGED_BEACON_ENABLED	= 1<<9,
	BSS_CHANGED_CQM			= 1<<10,
	BSS_CHANGED_IBSS		= 1<<11,
	BSS_CHANGED_ARP_FILTER		= 1<<12,
	BSS_CHANGED_QOS			= 1<<13,
	BSS_CHANGED_IDLE		= 1<<14,
	BSS_CHANGED_SSID		= 1<<15,
	BSS_CHANGED_PS			= 1<<16,
	BSS_CHANGED_CHANNEL		= 1<<17, // XXX: COMBO: should this be merged with _HT?
	BSS_CHANGED_RETRY_LIMITS	= 1<<18,
	BSS_CHANGED_P2P_PS		= 1<<19,
#ifdef IPV6_FILTERING
	BSS_CHANGED_NDP_FILTER		= 1<<20,
#endif /*IPV6_FILTERING*/
	BSS_CHANGED_STA_RESTART		= 1<<21,
	/* when adding here, make sure to change ieee80211_reconfig */
};

/*
 * The maximum number of IPv4 addresses listed for ARP filtering. If the number
 * of addresses for an interface increase beyond this value, hardware ARP
 * filtering will be disabled.
 */
#define IEEE80211_BSS_ARP_ADDR_LIST_LEN 4

#ifdef IPV6_FILTERING
/*
 * The maximum number of IPv6 addresses listed for NDP filtering. If the number
 * of addresses for an interface increase beyond this value, hardware NDP
 * filtering will be disabled.
 */
#define IEEE80211_BSS_NDP_ADDR_LIST_LEN 4
#endif /*IPV6_FILTERING*/


#define IEEE80211_TX_CTL_STBC_SHIFT		23
/* there are 40 bytes if you don't need the rateset to be kept */
#define IEEE80211_TX_INFO_DRIVER_DATA_SIZE 40

/* if you do need the rateset, then you have less space */
#define IEEE80211_TX_INFO_RATE_DRIVER_DATA_SIZE 24

/* maximum number of rate stages */
#define IEEE80211_TX_MAX_RATES	5
/**
 * enum mac80211_rx_flags - receive flags
 *
 * These flags are used with the @flag member of &struct ieee80211_rx_status.
 * @RX_FLAG_MMIC_ERROR: Michael MIC error was reported on this frame.
 *	Use together with %RX_FLAG_MMIC_STRIPPED.
 * @RX_FLAG_DECRYPTED: This frame was decrypted in hardware.
 * @RX_FLAG_MMIC_STRIPPED: the Michael MIC is stripped off this frame,
 *	verification has been done by the hardware.
 * @RX_FLAG_IV_STRIPPED: The IV/ICV are stripped from this frame.
 *	If this flag is set, the stack cannot do any replay detection
 *	hence the driver or hardware will have to do that.
 * @RX_FLAG_FAILED_FCS_CRC: Set this flag if the FCS check failed on
 *	the frame.
 * @RX_FLAG_FAILED_PLCP_CRC: Set this flag if the PCLP check failed on
 *	the frame.
 * @RX_FLAG_MACTIME_MPDU: The timestamp passed in the RX status (@mactime
 *	field) is valid and contains the time the first symbol of the MPDU
 *	was received. This is useful in monitor mode and for proper IBSS
 *	merging.
 * @RX_FLAG_SHORTPRE: Short preamble was used for this frame
 * @RX_FLAG_HT: HT MCS was used and rate_idx is MCS index
 * @RX_FLAG_40MHZ: HT40 (40 MHz) was used
 * @RX_FLAG_SHORT_GI: Short guard interval was used
 */
enum mac80211_rx_flags {
	RX_FLAG_MMIC_ERROR	= 1<<0,
	RX_FLAG_DECRYPTED	= 1<<1,
	RX_FLAG_MMIC_STRIPPED	= 1<<3,
	RX_FLAG_IV_STRIPPED	= 1<<4,
	RX_FLAG_FAILED_FCS_CRC	= 1<<5,
	RX_FLAG_FAILED_PLCP_CRC = 1<<6,
	RX_FLAG_MACTIME_MPDU	= 1<<7,
	RX_FLAG_SHORTPRE	= 1<<8,
	RX_FLAG_HT		= 1<<9,
	RX_FLAG_40MHZ		= 1<<10,
	RX_FLAG_SHORT_GI	= 1<<11,
	RX_FLAG_HW_CHKSUM_ERROR = 1<<12,
	RX_FLAG_STA_LISTEN  = 1<<13,
};

/**
 * struct ieee80211_rx_status - receive status
 *
 * The low-level driver should provide this information (the subset
 * supported by hardware) to the 802.11 code with each received
 * frame, in the skb's control buffer (cb).
 *
 * @mactime: value in microseconds of the 64-bit Time Synchronization Function
 * 	(TSF) timer when the first data symbol (MPDU) arrived at the hardware.
 * @band: the active band when this frame was received
 * @freq: frequency the radio was tuned to when receiving this frame, in MHz
 * @signal: signal strength when receiving this frame, either in dBm, in dB or
 *	unspecified depending on the hardware capabilities flags
 *	@IEEE80211_HW_SIGNAL_*
 * @antenna: antenna used
 * @rate_idx: index of data rate into band's supported rates or MCS index if
 *	HT rates are use (RX_FLAG_HT)
 * @flag: %RX_FLAG_*
 * @rx_flags: internal RX flags for mac80211
 */
struct ieee80211_rx_status {
	u64 mactime;
	enum ieee80211_band band;
	int freq;
	int signal;
	int antenna;
	int rate_idx;
	int flag;
	unsigned int rx_flags;
};

/**
 * enum ieee80211_key_flags - key flags
 *
 * These flags are used for communication about keys between the driver
 * and mac80211, with the @flags parameter of &struct ieee80211_key_conf.
 *
 * @IEEE80211_KEY_FLAG_WMM_STA: Set by mac80211, this flag indicates
 *	that the STA this key will be used with could be using QoS.
 * @IEEE80211_KEY_FLAG_GENERATE_IV: This flag should be set by the
 *	driver to indicate that it requires IV generation for this
 *	particular key.
 * @IEEE80211_KEY_FLAG_GENERATE_MMIC: This flag should be set by
 *	the driver for a TKIP key if it requires Michael MIC
 *	generation in software.
 * @IEEE80211_KEY_FLAG_PAIRWISE: Set by mac80211, this flag indicates
 *	that the key is pairwise rather then a shared key.
 * @IEEE80211_KEY_FLAG_SW_MGMT: This flag should be set by the driver for a
 *	CCMP key if it requires CCMP encryption of management frames (MFP) to
 *	be done in software.
 */
enum ieee80211_key_flags {
	IEEE80211_KEY_FLAG_WMM_STA	= 1<<0,
	IEEE80211_KEY_FLAG_GENERATE_IV	= 1<<1,
	IEEE80211_KEY_FLAG_GENERATE_MMIC= 1<<2,
	IEEE80211_KEY_FLAG_PAIRWISE	= 1<<3,
	IEEE80211_KEY_FLAG_SW_MGMT	= 1<<4,
	IEEE80211_KEY_FLAG_ALLOC_IV	= 1<<5,
};

/**
 * struct ieee80211_key_conf - key information
 *
 * This key information is given by mac80211 to the driver by
 * the set_key() callback in &struct ieee80211_ops.
 *
 * @hw_key_idx: To be set by the driver, this is the key index the driver
 *	wants to be given when a frame is transmitted and needs to be
 *	encrypted in hardware.
 * @cipher: The key's cipher suite selector.
 * @flags: key flags, see &enum ieee80211_key_flags.
 * @keyidx: the key index (0-3)
 * @keylen: key material length
 * @key: key material. For ALG_TKIP the key is encoded as a 256-bit (32 byte)
 * 	data block:
 * 	- Temporal Encryption Key (128 bits)
 * 	- Temporal Authenticator Tx MIC Key (64 bits)
 * 	- Temporal Authenticator Rx MIC Key (64 bits)
 * @icv_len: The ICV length for this key type
 * @iv_len: The IV length for this key type
 */
struct ieee80211_key_conf {
	u32 cipher;
	u8 icv_len;
	u8 iv_len;
	u8 hw_key_idx;
	u8 flags;
	s8 keyidx;
	u8 keylen;
	u8 key[0];
};

/**
 * struct ieee80211_sta - station table entry
 *
 * A station table entry represents a station we are possibly
 * communicating with. Since stations are RCU-managed in
 * mac80211, any ieee80211_sta pointer you get access to must
 * either be protected by rcu_read_lock() explicitly or implicitly,
 * or you must take good care to not use such a pointer after a
 * call to your sta_remove callback that removed it.
 *
 * @addr: MAC address
 * @aid: AID we assigned to the station if we're an AP
 * @supp_rates: Bitmap of supported rates (per band)
 * @ht_cap: HT capabilities of this STA; restricted to our own TX capabilities
 * @wme: indicates whether the STA supports WME. Only valid during AP-mode.
 * @drv_priv: data area for driver use, will always be aligned to
 *	sizeof(void *), size is determined in hw information.
 * @uapsd_queues: bitmap of queues configured for uapsd. Only valid
 *	if wme is supported.
 * @max_sp: max Service Period. Only valid if wme is supported.
 */
struct ieee80211_sta {
	u32 supp_rates[IEEE80211_NUM_BANDS];
	u8 addr[ETH_ALEN];
	u16 aid;
	struct ieee80211_sta_ht_cap ht_cap;
	bool wme;
	u8 uapsd_queues;
	u8 max_sp;
	struct atbm_wpa_ie_data wpa_sta_data;
};


/**
 * enum ieee80211_hw_flags - hardware flags
 *
 * These flags are used to indicate hardware capabilities to
 * the stack. Generally, flags here should have their meaning
 * done in a way that the simplest hardware doesn't need setting
 * any particular flags. There are some exceptions to this rule,
 * however, so you are advised to review these flags carefully.
 *
 * @IEEE80211_HW_HAS_RATE_CONTROL:
 *	The hardware or firmware includes rate control, and cannot be
 *	controlled by the stack. As such, no rate control algorithm
 *	should be instantiated, and the TX rate reported to userspace
 *	will be taken from the TX status instead of the rate control
 *	algorithm.
 *	Note that this requires that the driver implement a number of
 *	callbacks so it has the correct information, it needs to have
 *	the @set_rts_threshold callback and must look at the BSS config
 *	@use_cts_prot for G/N protection, @use_short_slot for slot
 *	timing in 2.4 GHz and @use_short_preamble for preambles for
 *	CCK frames.
 *
 * @IEEE80211_HW_RX_INCLUDES_FCS:
 *	Indicates that received frames passed to the stack include
 *	the FCS at the end.
 *
 * @IEEE80211_HW_HOST_BROADCAST_PS_BUFFERING:
 *	Some wireless LAN chipsets buffer broadcast/multicast frames
 *	for power saving stations in the hardware/firmware and others
 *	rely on the host system for such buffering. This option is used
 *	to configure the IEEE 802.11 upper layer to buffer broadcast and
 *	multicast frames when there are power saving stations so that
 *	the driver can fetch them with ieee80211_get_buffered_bc().
 *
 * @IEEE80211_HW_2GHZ_SHORT_SLOT_INCAPABLE:
 *	Hardware is not capable of short slot operation on the 2.4 GHz band.
 *
 * @IEEE80211_HW_2GHZ_SHORT_PREAMBLE_INCAPABLE:
 *	Hardware is not capable of receiving frames with short preamble on
 *	the 2.4 GHz band.
 *
 * @IEEE80211_HW_SIGNAL_UNSPEC:
 *	Hardware can provide signal values but we don't know its units. We
 *	expect values between 0 and @max_signal.
 *	If possible please provide dB or dBm instead.
 *
 * @IEEE80211_HW_SIGNAL_DBM:
 *	Hardware gives signal values in dBm, decibel difference from
 *	one milliwatt. This is the preferred method since it is standardized
 *	between different devices. @max_signal does not need to be set.
 *
 * @IEEE80211_HW_SPECTRUM_MGMT:
 * 	Hardware supports spectrum management defined in 802.11h
 * 	Measurement, Channel Switch, Quieting, TPC
 *
 * @IEEE80211_HW_AMPDU_AGGREGATION:
 *	Hardware supports 11n A-MPDU aggregation.
 *
 * @IEEE80211_HW_SUPPORTS_PS:
 *	Hardware has power save support (i.e. can go to sleep).
 *
 * @IEEE80211_HW_PS_NULLFUNC_STACK:
 *	Hardware requires nullfunc frame handling in stack, implies
 *	stack support for dynamic PS.
 *
 * @IEEE80211_HW_SUPPORTS_DYNAMIC_PS:
 *	Hardware has support for dynamic PS.
 *
 * @IEEE80211_HW_MFP_CAPABLE:
 *	Hardware supports management frame protection (MFP, IEEE 802.11w).
 *
 * @IEEE80211_HW_BEACON_FILTER:
 *	Hardware supports dropping of irrelevant beacon frames to
 *	avoid waking up cpu.
 *
 * @IEEE80211_HW_SUPPORTS_STATIC_SMPS:
 *	Hardware supports static spatial multiplexing powersave,
 *	ie. can turn off all but one chain even on HT connections
 *	that should be using more chains.
 *
 * @IEEE80211_HW_SUPPORTS_DYNAMIC_SMPS:
 *	Hardware supports dynamic spatial multiplexing powersave,
 *	ie. can turn off all but one chain and then wake the rest
 *	up as required after, for example, rts/cts handshake.
 *
 * @IEEE80211_HW_SUPPORTS_UAPSD:
 *	Hardware supports Unscheduled Automatic Power Save Delivery
 *	(U-APSD) in managed mode. The mode is configured with
 *	conf_tx() operation.
 *
 * @IEEE80211_HW_REPORTS_TX_ACK_STATUS:
 *	Hardware can provide ack status reports of Tx frames to
 *	the stack.
 *
 * @IEEE80211_HW_CONNECTION_MONITOR:
 *      The hardware performs its own connection monitoring, including
 *      periodic keep-alives to the AP and probing the AP on beacon loss.
 *      When this flag is set, signaling beacon-loss will cause an immediate
 *      change to disassociated state.
 *
 * @IEEE80211_HW_SUPPORTS_CQM_RSSI:
 *	Hardware can do connection quality monitoring - i.e. it can monitor
 *	connection quality related parameters, such as the RSSI level and
 *	provide notifications if configured trigger levels are reached.
 *
 * @IEEE80211_HW_NEED_DTIM_PERIOD:
 *	This device needs to know the DTIM period for the BSS before
 *	associating.
 *
 * @IEEE80211_HW_SUPPORTS_PER_STA_GTK: The device's crypto engine supports
 *	per-station GTKs as used by IBSS RSN or during fast transition. If
 *	the device doesn't support per-station GTKs, but can be asked not
 *	to decrypt group addressed frames, then IBSS RSN support is still
 *	possible but software crypto will be used. Advertise the wiphy flag
 *	only in that case.
 *
 * @IEEE80211_HW_AP_LINK_PS: When operating in AP mode the device
 *	autonomously manages the PS status of connected stations. When
 *	this flag is set mac80211 will not trigger PS mode for connected
 *	stations based on the PM bit of incoming frames.
 *	Use ieee80211_start_ps()/ieee8021_end_ps() to manually configure
 *	the PS mode of connected stations.
 *
 * @IEEE80211_HW_TX_AMPDU_SETUP_IN_HW: The device handles TX A-MPDU session
 *      setup strictly in HW. mac80211 should not attempt to do this in
 *      software.
 *
 * @IEEE80211_HW_SUPPORTS_CQM_BEACON_MISS
 *      Connection quality monitoring - beacon miss.
 *
 * @IEEE80211_HW_SUPPORTS_CQM_TX_FAIL
 *      Connection quality monitoring - tx failure.
 *
 * @IEEE80211_HW_SUPPORTS_MULTI_CHANNEL
 *      Hardware supports simultaneous operation on different channels.
 *
 * @IEEE80211_HW_QUEUE_CONTROL: The driver wants to control per-interface
 *	queue mapping in order to use different queues (not just one per AC)
 *	for different virtual interfaces. See the doc section on HW queue
 *	control for more details.
 */
enum ieee80211_hw_flags {
	IEEE80211_HW_HAS_RATE_CONTROL			= 1<<0,
	IEEE80211_HW_RX_INCLUDES_FCS			= 1<<1,
	IEEE80211_HW_HOST_BROADCAST_PS_BUFFERING	= 1<<2,
	IEEE80211_HW_2GHZ_SHORT_SLOT_INCAPABLE		= 1<<3,
	IEEE80211_HW_2GHZ_SHORT_PREAMBLE_INCAPABLE	= 1<<4,
	IEEE80211_HW_SIGNAL_UNSPEC			= 1<<5,
	IEEE80211_HW_SIGNAL_DBM				= 1<<6,
	IEEE80211_HW_NEED_DTIM_PERIOD			= 1<<7,
	IEEE80211_HW_SPECTRUM_MGMT			= 1<<8,
	IEEE80211_HW_AMPDU_AGGREGATION			= 1<<9,
	IEEE80211_HW_SUPPORTS_PS			= 1<<10,
	IEEE80211_HW_PS_NULLFUNC_STACK			= 1<<11,
	IEEE80211_HW_SUPPORTS_DYNAMIC_PS		= 1<<12,
	IEEE80211_HW_MFP_CAPABLE			= 1<<13,
	IEEE80211_HW_BEACON_FILTER			= 1<<14,
	IEEE80211_HW_SUPPORTS_STATIC_SMPS		= 1<<15,
	IEEE80211_HW_SUPPORTS_DYNAMIC_SMPS		= 1<<16,
	IEEE80211_HW_SUPPORTS_UAPSD			= 1<<17,
	IEEE80211_HW_REPORTS_TX_ACK_STATUS		= 1<<18,
	IEEE80211_HW_CONNECTION_MONITOR			= 1<<19,
	IEEE80211_HW_SUPPORTS_CQM_RSSI			= 1<<20,
	IEEE80211_HW_SUPPORTS_PER_STA_GTK		= 1<<21,
	IEEE80211_HW_AP_LINK_PS				= 1<<22,
	IEEE80211_HW_TX_AMPDU_SETUP_IN_HW		= 1<<23,
	IEEE80211_HW_SUPPORTS_CQM_BEACON_MISS		= 1<<24,
	IEEE80211_HW_SUPPORTS_CQM_TX_FAIL		= 1<<25,
	IEEE80211_HW_SUPPORTS_P2P_PS			= 1<<26,
	IEEE80211_HW_SUPPORTS_MULTI_CHANNEL		= 1<<27,
	IEEE80211_HW_QUEUE_CONTROL			= 1<<28,
};

/**
 * struct ieee80211_hw - hardware information and state
 *
 * This structure contains the configuration and hardware
 * information for an 802.11 PHY.
 *
 * @wiphy: This points to the &struct wiphy allocated for this
 *	802.11 PHY. You must fill in the @perm_addr and @dev
 *	members of this structure using SET_IEEE80211_DEV()
 *	and SET_IEEE80211_PERM_ADDR(). Additionally, all supported
 *	bands (with channels, bitrates) are registered here.
 *
 * @conf: &struct ieee80211_conf, device configuration, don't use.
 *
 * @priv: pointer to private area that was allocated for driver use
 *	along with this structure.
 *
 * @flags: hardware flags, see &enum ieee80211_hw_flags.
 *
 * @extra_tx_headroom: headroom to reserve in each transmit skb
 *	for use by the driver (e.g. for transmit headers.)
 *
 * @channel_change_time: time (in microseconds) it takes to change channels.
 *
 * @max_signal: Maximum value for signal (rssi) in RX information, used
 *     only when @IEEE80211_HW_SIGNAL_UNSPEC or @IEEE80211_HW_SIGNAL_DB
 *
 * @max_listen_interval: max listen interval in units of beacon interval
 *     that HW supports
 *
 * @queues: number of available hardware transmit queues for
 *	data packets. WMM/QoS requires at least four, these
 *	queues need to have configurable access parameters.
 *
 * @rate_control_algorithm: rate control algorithm for this hardware.
 *	If unset (NULL), the default algorithm will be used. Must be
 *	set before calling ieee80211_register_hw().
 *
 * @vif_data_size: size (in bytes) of the drv_priv data area
 *	within &struct ieee80211_vif.
 * @sta_data_size: size (in bytes) of the drv_priv data area
 *	within &struct ieee80211_sta.
 *
 * @max_rates: maximum number of alternate rate retry stages the hw
 *	can handle.
 * @max_report_rates: maximum number of alternate rate retry stages
 *	the hw can report back.
 * @max_rate_tries: maximum number of tries for each stage
 *
 * @napi_weight: weight used for NAPI polling.  You must specify an
 *	appropriate value here if a napi_poll operation is provided
 *	by your driver.
 *
 * @max_rx_aggregation_subframes: maximum buffer size (number of
 *	sub-frames) to be used for A-MPDU block ack receiver
 *	aggregation.
 *	This is only relevant if the device has restrictions on the
 *	number of subframes, if it relies on mac80211 to do reordering
 *	it shouldn't be set.
 *
 * @max_tx_aggregation_subframes: maximum number of subframes in an
 *	aggregate an HT driver will transmit, used by the peer as a
 *	hint to size its reorder buffer.
 *
 * @offchannel_tx_hw_queue: HW queue ID to use for offchannel TX
 *	(if %IEEE80211_HW_QUEUE_CONTROL is set)
 */
/**
 * DOC: Hardware crypto acceleration
 *
 * mac80211 is capable of taking advantage of many hardware
 * acceleration designs for encryption and decryption operations.
 *
 * The set_key() callback in the &struct ieee80211_ops for a given
 * device is called to enable hardware acceleration of encryption and
 * decryption. The callback takes a @sta parameter that will be NULL
 * for default keys or keys used for transmission only, or point to
 * the station information for the peer for individual keys.
 * Multiple transmission keys with the same key index may be used when
 * VLANs are configured for an access point.
 *
 * When transmitting, the TX control data will use the @hw_key_idx
 * selected by the driver by modifying the &struct ieee80211_key_conf
 * pointed to by the @key parameter to the set_key() function.
 *
 * The set_key() call for the %SET_KEY command should return 0 if
 * the key is now in use, -%EOPNOTSUPP or -%ENOSPC if it couldn't be
 * added; if you return 0 then hw_key_idx must be assigned to the
 * hardware key index, you are free to use the full u8 range.
 *
 * When the cmd is %DISABLE_KEY then it must succeed.
 *
 * Note that it is permissible to not decrypt a frame even if a key
 * for it has been uploaded to hardware, the stack will not make any
 * decision based on whether a key has been uploaded or not but rather
 * based on the receive flags.
 *
 * The &struct ieee80211_key_conf structure pointed to by the @key
 * parameter is guaranteed to be valid until another call to set_key()
 * removes it, but it can only be used as a cookie to differentiate
 * keys.
 *
 * In TKIP some HW need to be provided a phase 1 key, for RX decryption
 * acceleration (i.e. iwlwifi). Those drivers should provide update_tkip_key
 * handler.
 * The update_tkip_key() call updates the driver with the new phase 1 key.
 * This happens every time the iv16 wraps around (every 65536 packets). The
 * set_key() call will happen only once for each key (unless the AP did
 * rekeying), it will not include a valid phase 1 key. The valid phase 1 key is
 * provided by update_tkip_key only. The trigger that makes mac80211 call this
 * handler is software decryption with wrap around of iv16.
 */

/**
 * DOC: Powersave support
 *
 * mac80211 has support for various powersave implementations.
 *
 * First, it can support hardware that handles all powersaving by itself,
 * such hardware should simply set the %IEEE80211_HW_SUPPORTS_PS hardware
 * flag. In that case, it will be told about the desired powersave mode
 * with the %IEEE80211_CONF_PS flag depending on the association status.
 * The hardware must take care of sending nullfunc frames when necessary,
 * i.e. when entering and leaving powersave mode. The hardware is required
 * to look at the AID in beacons and signal to the AP that it woke up when
 * it finds traffic directed to it.
 *
 * %IEEE80211_CONF_PS flag enabled means that the powersave mode defined in
 * IEEE 802.11-2007 section 11.2 is enabled. This is not to be confused
 * with hardware wakeup and sleep states. Driver is responsible for waking
 * up the hardware before issuing commands to the hardware and putting it
 * back to sleep at appropriate times.
 *
 * When PS is enabled, hardware needs to wakeup for beacons and receive the
 * buffered multicast/broadcast frames after the beacon. Also it must be
 * possible to send frames and receive the acknowledment frame.
 *
 * Other hardware designs cannot send nullfunc frames by themselves and also
 * need software support for parsing the TIM bitmap. This is also supported
 * by mac80211 by combining the %IEEE80211_HW_SUPPORTS_PS and
 * %IEEE80211_HW_PS_NULLFUNC_STACK flags. The hardware is of course still
 * required to pass up beacons. The hardware is still required to handle
 * waking up for multicast traffic; if it cannot the driver must handle that
 * as best as it can, mac80211 is too slow to do that.
 *
 * Dynamic powersave is an extension to normal powersave in which the
 * hardware stays awake for a user-specified period of time after sending a
 * frame so that reply frames need not be buffered and therefore delayed to
 * the next wakeup. It's compromise of getting good enough latency when
 * there's data traffic and still saving significantly power in idle
 * periods.
 *
 * Dynamic powersave is simply supported by mac80211 enabling and disabling
 * PS based on traffic. Driver needs to only set %IEEE80211_HW_SUPPORTS_PS
 * flag and mac80211 will handle everything automatically. Additionally,
 * hardware having support for the dynamic PS feature may set the
 * %IEEE80211_HW_SUPPORTS_DYNAMIC_PS flag to indicate that it can support
 * dynamic PS mode itself. The driver needs to look at the
 * @dynamic_ps_timeout hardware configuration value and use it that value
 * whenever %IEEE80211_CONF_PS is set. In this case mac80211 will disable
 * dynamic PS feature in stack and will just keep %IEEE80211_CONF_PS
 * enabled whenever user has enabled powersave.
 *
 * Some hardware need to toggle a single shared antenna between WLAN and
 * Bluetooth to facilitate co-existence. These types of hardware set
 * limitations on the use of host controlled dynamic powersave whenever there
 * is simultaneous WLAN and Bluetooth traffic. For these types of hardware, the
 * driver may request temporarily going into full power save, in order to
 * enable toggling the antenna between BT and WLAN. If the driver requests
 * disabling dynamic powersave, the @dynamic_ps_timeout value will be
 * temporarily set to zero until the driver re-enables dynamic powersave.
 *
 * Driver informs U-APSD client support by enabling
 * %IEEE80211_HW_SUPPORTS_UAPSD flag. The mode is configured through the
 * uapsd paramater in conf_tx() operation. Hardware needs to send the QoS
 * Nullfunc frames and stay awake until the service period has ended. To
 * utilize U-APSD, dynamic powersave is disabled for voip AC and all frames
 * from that AC are transmitted with powersave enabled.
 *
 * Note: U-APSD client mode is not yet supported with
 * %IEEE80211_HW_PS_NULLFUNC_STACK.
 */

/**
 * DOC: Beacon filter support
 *
 * Some hardware have beacon filter support to reduce host cpu wakeups
 * which will reduce system power consumption. It usuallly works so that
 * the firmware creates a checksum of the beacon but omits all constantly
 * changing elements (TSF, TIM etc). Whenever the checksum changes the
 * beacon is forwarded to the host, otherwise it will be just dropped. That
 * way the host will only receive beacons where some relevant information
 * (for example ERP protection or WMM settings) have changed.
 *
 * Beacon filter support is advertised with the %IEEE80211_HW_BEACON_FILTER
 * hardware capability. The driver needs to enable beacon filter support
 * whenever power save is enabled, that is %IEEE80211_CONF_PS is set. When
 * power save is enabled, the stack will not check for beacon loss and the
 * driver needs to notify about loss of beacons with ieee80211_beacon_loss().
 *
 * The time (or number of beacons missed) until the firmware notifies the
 * driver of a beacon loss event (which in turn causes the driver to call
 * ieee80211_beacon_loss()) should be configurable and will be controlled
 * by mac80211 and the roaming algorithm in the future.
 *
 * Since there may be constantly changing information elements that nothing
 * in the software stack cares about, we will, in the future, have mac80211
 * tell the driver which information elements are interesting in the sense
 * that we want to see changes in them. This will include
 *  - a list of information element IDs
 *  - a list of OUIs for the vendor information element
 *
 * Ideally, the hardware would filter out any beacons without changes in the
 * requested elements, but if it cannot support that it may, at the expense
 * of some efficiency, filter out only a subset. For example, if the device
 * doesn't support checking for OUIs it should pass up all changes in all
 * vendor information elements.
 *
 * Note that change, for the sake of simplification, also includes information
 * elements appearing or disappearing from the beacon.
 *
 * Some hardware supports an "ignore list" instead, just make sure nothing
 * that was requested is on the ignore list, and include commonly changing
 * information element IDs in the ignore list, for example 11 (BSS load) and
 * the various vendor-assigned IEs with unknown contents (128, 129, 133-136,
 * 149, 150, 155, 156, 173, 176, 178, 179, 219); for forward compatibility
 * it could also include some currently unused IDs.
 *
 *
 * In addition to these capabilities, hardware should support notifying the
 * host of changes in the beacon RSSI. This is relevant to implement roaming
 * when no traffic is flowing (when traffic is flowing we see the RSSI of
 * the received data packets). This can consist in notifying the host when
 * the RSSI changes significantly or when it drops below or rises above
 * configurable thresholds. In the future these thresholds will also be
 * configured by mac80211 (which gets them from userspace) to implement
 * them as the roaming algorithm requires.
 *
 * If the hardware cannot implement this, the driver should ask it to
 * periodically pass beacon frames to the host so that software can do the
 * signal strength threshold checking.
 */

/**
 * DOC: Spatial multiplexing power save
 *
 * SMPS (Spatial multiplexing power save) is a mechanism to conserve
 * power in an 802.11n implementation. For details on the mechanism
 * and rationale, please refer to 802.11 (as amended by 802.11n-2009)
 * "11.2.3 SM power save".
 *
 * The mac80211 implementation is capable of sending action frames
 * to update the AP about the station's SMPS mode, and will instruct
 * the driver to enter the specific mode. It will also announce the
 * requested SMPS mode during the association handshake. Hardware
 * support for this feature is required, and can be indicated by
 * hardware flags.
 *
 * The default mode will be "automatic", which nl80211/cfg80211
 * defines to be dynamic SMPS in (regular) powersave, and SMPS
 * turned off otherwise.
 *
 * To support this feature, the driver must set the appropriate
 * hardware support flags, and handle the SMPS flag to the config()
 * operation. It will then with this mechanism be instructed to
 * enter the requested SMPS mode while associated to an HT AP.
 */

/**
 * DOC: Frame filtering
 *
 * mac80211 requires to see many management frames for proper
 * operation, and users may want to see many more frames when
 * in monitor mode. However, for best CPU usage and power consumption,
 * having as few frames as possible percolate through the stack is
 * desirable. Hence, the hardware should filter as much as possible.
 *
 * To achieve this, mac80211 uses filter flags (see below) to tell
 * the driver's configure_filter() function which frames should be
 * passed to mac80211 and which should be filtered out.
 *
 * Before configure_filter() is invoked, the prepare_multicast()
 * callback is invoked with the parameters @mc_count and @mc_list
 * for the combined multicast address list of all virtual interfaces.
 * It's use is optional, and it returns a u64 that is passed to
 * configure_filter(). Additionally, configure_filter() has the
 * arguments @changed_flags telling which flags were changed and
 * @total_flags with the new flag states.
 *
 * If your device has no multicast address filters your driver will
 * need to check both the %FIF_ALLMULTI flag and the @mc_count
 * parameter to see whether multicast frames should be accepted
 * or dropped.
 *
 * All unsupported flags in @total_flags must be cleared.
 * Hardware does not support a flag if it is incapable of _passing_
 * the frame to the stack. Otherwise the driver must ignore
 * the flag, but not clear it.
 * You must _only_ clear the flag (announce no support for the
 * flag to mac80211) if you are not able to pass the packet type
 * to the stack (so the hardware always filters it).
 * So for example, you should clear @FIF_CONTROL, if your hardware
 * always filters control frames. If your hardware always passes
 * control frames to the kernel and is incapable of filtering them,
 * you do _not_ clear the @FIF_CONTROL flag.
 * This rule applies to all other FIF flags as well.
 */

/**
 * DOC: AP support for powersaving clients
 *
 * In order to implement AP and P2P GO modes, mac80211 has support for
 * client powersaving, both "legacy" PS (PS-Poll/null data) and uAPSD.
 * There currently is no support for sAPSD.
 *
 * There is one assumption that mac80211 makes, namely that a client
 * will not poll with PS-Poll and trigger with uAPSD at the same time.
 * Both are supported, and both can be used by the same client, but
 * they can't be used concurrently by the same client. This simplifies
 * the driver code.
 *
 * The first thing to keep in mind is that there is a flag for complete
 * driver implementation: %IEEE80211_HW_AP_LINK_PS. If this flag is set,
 * mac80211 expects the driver to handle most of the state machine for
 * powersaving clients and will ignore the PM bit in incoming frames.
 * Drivers then use ieee80211_sta_ps_transition() to inform mac80211 of
 * stations' powersave transitions. In this mode, mac80211 also doesn't
 * handle PS-Poll/uAPSD.
 *
 * In the mode without %IEEE80211_HW_AP_LINK_PS, mac80211 will check the
 * PM bit in incoming frames for client powersave transitions. When a
 * station goes to sleep, we will stop transmitting to it. There is,
 * however, a race condition: a station might go to sleep while there is
 * data buffered on hardware queues. If the device has support for this
 * it will reject frames, and the driver should give the frames back to
 * mac80211 with the %IEEE80211_TX_STAT_TX_FILTERED flag set which will
 * cause mac80211 to retry the frame when the station wakes up. The
 * driver is also notified of powersave transitions by calling its
 * @sta_notify callback.
 *
 * When the station is asleep, it has three choices: it can wake up,
 * it can PS-Poll, or it can possibly start a uAPSD service period.
 * Waking up is implemented by simply transmitting all buffered (and
 * filtered) frames to the station. This is the easiest case. When
 * the station sends a PS-Poll or a uAPSD trigger frame, mac80211
 * will inform the driver of this with the @allow_buffered_frames
 * callback; this callback is optional. mac80211 will then transmit
 * the frames as usual and set the %IEEE80211_TX_CTL_POLL_RESPONSE
 * on each frame. The last frame in the service period (or the only
 * response to a PS-Poll) also has %IEEE80211_TX_STATUS_EOSP set to
 * indicate that it ends the service period; as this frame must have
 * TX status report it also sets %IEEE80211_TX_CTL_REQ_TX_STATUS.
 * When TX status is reported for this frame, the service period is
 * marked has having ended and a new one can be started by the peer.
 *
 * Another race condition can happen on some devices like iwlwifi
 * when there are frames queued for the station and it wakes up
 * or polls; the frames that are already queued could end up being
 * transmitted first instead, causing reordering and/or wrong
 * processing of the EOSP. The cause is that allowing frames to be
 * transmitted to a certain station is out-of-band communication to
 * the device. To allow this problem to be solved, the driver can
 * call ieee80211_sta_block_awake() if frames are buffered when it
 * is notified that the station went to sleep. When all these frames
 * have been filtered (see above), it must call the function again
 * to indicate that the station is no longer blocked.
 *
 * If the driver buffers frames in the driver for aggregation in any
 * way, it must use the ieee80211_sta_set_buffered() call when it is
 * notified of the station going to sleep to inform mac80211 of any
 * TIDs that have frames buffered. Note that when a station wakes up
 * this information is reset (hence the requirement to call it when
 * informed of the station going to sleep). Then, when a service
 * period starts for any reason, @release_buffered_frames is called
 * with the number of frames to be released and which TIDs they are
 * to come from. In this case, the driver is responsible for setting
 * the EOSP (for uAPSD) and MORE_DATA bits in the released frames,
 * to help the @more_data paramter is passed to tell the driver if
 * there is more data on other TIDs -- the TIDs to release frames
 * from are ignored since mac80211 doesn't know how many frames the
 * buffers for those TIDs contain.
 *
 * If the driver also implement GO mode, where absence periods may
 * shorten service periods (or abort PS-Poll responses), it must
 * filter those response frames except in the case of frames that
 * are buffered in the driver -- those must remain buffered to avoid
 * reordering. Because it is possible that no frames are released
 * in this case, the driver must call ieee80211_sta_eosp_irqsafe()
 * to indicate to mac80211 that the service period ended anyway.
 *
 * Finally, if frames from multiple TIDs are released from mac80211
 * but the driver might reorder them, it must clear & set the flags
 * appropriately (only the last frame may have %IEEE80211_TX_STATUS_EOSP)
 * and also take care of the EOSP and MORE_DATA bits in the frame.
 * The driver may also use ieee80211_sta_eosp_irqsafe() in this case.
 */

/**
 * DOC: HW queue control
 *
 * Before HW queue control was introduced, mac80211 only had a single static
 * assignment of per-interface AC software queues to hardware queues. This
 * was problematic for a few reasons:
 * 1) off-channel transmissions might get stuck behind other frames
 * 2) multiple virtual interfaces couldn't be handled correctly
 * 3) after-DTIM frames could get stuck behind other frames
 *
 * To solve this, hardware typically uses multiple different queues for all
 * the different usages, and this needs to be propagated into mac80211 so it
 * won't have the same problem with the software queues.
 *
 * Therefore, mac80211 now offers the %IEEE80211_HW_QUEUE_CONTROL capability
 * flag that tells it that the driver implements its own queue control. To do
 * so, the driver will set up the various queues in each &struct ieee80211_vif
 * and the offchannel queue in &struct ieee80211_hw. In response, mac80211 will
 * use those queue IDs in the hw_queue field of &struct ieee80211_tx_info and
 * if necessary will queue the frame on the right software queue that mirrors
 * the hardware queue.
 * Additionally, the driver has to then use these HW queue IDs for the queue
 * management functions (ieee80211_stop_queue() et al.)
 *
 * The driver is free to set up the queue mappings as needed, multiple virtual
 * interfaces may map to the same hardware queues if needed. The setup has to
 * happen during add_interface or change_interface callbacks. For example, a
 * driver supporting station+station and station+AP modes might decide to have
 * 10 hardware queues to handle different scenarios:
 *
 * 4 AC HW queues for 1st vif: 0, 1, 2, 3
 * 4 AC HW queues for 2nd vif: 4, 5, 6, 7
 * after-DTIM queue for AP:   8
 * off-channel queue:         9
 *
 * It would then set up the hardware like this:
 *   hw.offchannel_tx_hw_queue = 9
 *
 * and the first virtual interface that is added as follows:
 *   vif.hw_queue[IEEE80211_AC_VO] = 0
 *   vif.hw_queue[IEEE80211_AC_VI] = 1
 *   vif.hw_queue[IEEE80211_AC_BE] = 2
 *   vif.hw_queue[IEEE80211_AC_BK] = 3
 *   vif.cab_queue = 8 // if AP mode, otherwise %IEEE80211_INVAL_HW_QUEUE
 * and the second virtual interface with 4-7.
 *
 * If queue 6 gets full, for example, mac80211 would only stop the second
 * virtual interface's BE queue since virtual interface queues are per AC.
 *
 * Note that the vif.cab_queue value should be set to %IEEE80211_INVAL_HW_QUEUE
 * whenever the queue is not used (i.e. the interface is not in AP mode) if the
 * queue could potentially be shared since mac80211 will look at cab_queue when
 * a queue is stopped/woken even if the interface is not in AP mode.
 */

/**
 * enum ieee80211_filter_flags - hardware filter flags
 *
 * These flags determine what the filter in hardware should be
 * programmed to let through and what should not be passed to the
 * stack. It is always safe to pass more frames than requested,
 * but this has negative impact on power consumption.
 *
 * @FIF_PROMISC_IN_BSS: promiscuous mode within your BSS,
 *	think of the BSS as your network segment and then this corresponds
 *	to the regular ethernet device promiscuous mode.
 *
 * @FIF_ALLMULTI: pass all multicast frames, this is used if requested
 *	by the user or if the hardware is not capable of filtering by
 *	multicast address.
 *
 * @FIF_FCSFAIL: pass frames with failed FCS (but you need to set the
 *	%RX_FLAG_FAILED_FCS_CRC for them)
 *
 * @FIF_PLCPFAIL: pass frames with failed PLCP CRC (but you need to set
 *	the %RX_FLAG_FAILED_PLCP_CRC for them
 *
 * @FIF_BCN_PRBRESP_PROMISC: This flag is set during scanning to indicate
 *	to the hardware that it should not filter beacons or probe responses
 *	by BSSID. Filtering them can greatly reduce the amount of processing
 *	mac80211 needs to do and the amount of CPU wakeups, so you should
 *	honour this flag if possible.
 *
 * @FIF_CONTROL: pass control frames (except for PS Poll), if PROMISC_IN_BSS
 * 	is not set then only those addressed to this station.
 *
 * @FIF_OTHER_BSS: pass frames destined to other BSSes
 *
 * @FIF_PSPOLL: pass PS Poll frames, if PROMISC_IN_BSS is not set then only
 * 	those addressed to this station.
 *
 * @FIF_PROBE_REQ: pass probe request frames
 */
enum ieee80211_filter_flags {
	FIF_PROMISC_IN_BSS	= 1<<0,
	FIF_ALLMULTI		= 1<<1,
	FIF_FCSFAIL		= 1<<2,
	FIF_PLCPFAIL		= 1<<3,
	FIF_BCN_PRBRESP_PROMISC	= 1<<4,
	FIF_CONTROL		= 1<<5,
	FIF_OTHER_BSS		= 1<<6,
	FIF_PSPOLL		= 1<<7,
	FIF_PROBE_REQ		= 1<<8,
};

/**
 * enum ieee80211_ampdu_mlme_action - A-MPDU actions
 *
 * These flags are used with the ampdu_action() callback in
 * &struct ieee80211_ops to indicate which action is needed.
 *
 * Note that drivers MUST be able to deal with a TX aggregation
 * session being stopped even before they OK'ed starting it by
 * calling ieee80211_start_tx_ba_cb_irqsafe, because the peer
 * might receive the addBA frame and send a delBA right away!
 *
 * @IEEE80211_AMPDU_RX_START: start Rx aggregation
 * @IEEE80211_AMPDU_RX_STOP: stop Rx aggregation
 * @IEEE80211_AMPDU_TX_START: start Tx aggregation
 * @IEEE80211_AMPDU_TX_STOP: stop Tx aggregation
 * @IEEE80211_AMPDU_TX_OPERATIONAL: TX aggregation has become operational
 */
enum ieee80211_ampdu_mlme_action {
	IEEE80211_AMPDU_RX_START,
	IEEE80211_AMPDU_RX_STOP,
	IEEE80211_AMPDU_TX_START,
	IEEE80211_AMPDU_TX_STOP,
	IEEE80211_AMPDU_TX_OPERATIONAL,
};

/**
 * enum ieee80211_tx_sync_type - TX sync type
 * @IEEE80211_TX_SYNC_AUTH: sync TX for authentication
 *	(and possibly also before direct probe)
 * @IEEE80211_TX_SYNC_ASSOC: sync TX for association
 * @IEEE80211_TX_SYNC_ACTION: sync TX for action frame
 *	(not implemented yet)
 */
enum ieee80211_tx_sync_type {
	IEEE80211_TX_SYNC_AUTH,
	IEEE80211_TX_SYNC_ASSOC,
	IEEE80211_TX_SYNC_ACTION,
};

/**
 * enum ieee80211_frame_release_type - frame release reason
 * @IEEE80211_FRAME_RELEASE_PSPOLL: frame released for PS-Poll
 * @IEEE80211_FRAME_RELEASE_UAPSD: frame(s) released due to
 *	frame received on trigger-enabled AC
 */
enum ieee80211_frame_release_type {
	IEEE80211_FRAME_RELEASE_PSPOLL,
	IEEE80211_FRAME_RELEASE_UAPSD,
};

/*
 * The TX headroom reserved by mac80211 for its own tx_status functions.
 * This is enough for the radiotap header.
 */
#define IEEE80211_TX_STATUS_HEADROOM	14

struct atbm_ewma {
	unsigned long internal;
	unsigned long factor;
	unsigned long weight;
};
static inline int atbm_ilog2(unsigned long v)
{
	int l = 0;
	while ((1UL << l) < v)
		l++;
	return l;
}

static inline void atbm_ewma_init(struct atbm_ewma *avg, unsigned long factor, unsigned long weight)
{

	avg->weight = atbm_ilog2(weight);
	avg->factor = atbm_ilog2(factor);
	avg->internal = 0;
}
/**
 * ewma_add() - Exponentially weighted moving average (EWMA)
 * @avg: Average structure
 * @val: Current value
 *
 * Add a sample to the average.
 */
static inline struct atbm_ewma *atbm_ewma_add(struct atbm_ewma *avg, unsigned long val)
{
	avg->internal = avg->internal  ?
		(((avg->internal << avg->weight) - avg->internal) +
			(val << avg->factor)) >> avg->weight :
		(val << avg->factor);
	return avg;
}
#define ATBM_DIV_ROUND_CLOSEST(x, divisor)(			\
{							\
	typeof(divisor) __divisor = divisor;		\
	(((x) + ((__divisor) / 2)) / (__divisor));	\
}							\
)

static inline unsigned long atbm_ewma_read(const struct atbm_ewma *avg)
{
	return avg->internal >> avg->factor;
}
static inline const u8 *atbm_ieee80211_find_ie(u8 eid, const u8 *ies, int len)
{
	while (len > 2 && ies[0] != eid) {
		len -= ies[1] + 2;
		ies += ies[1] + 2;
	}
	if (len < 2)
		return NULL;
	if (len < 2 + ies[1])
		return NULL;
	return ies;
}

static inline const u8 *atbm_ieee80211_find_vendor_ie(unsigned int oui, u8 oui_type,
				  const u8 *ies, int len)
{
	struct atbm_ieee80211_vendor_ie *ie;
	const u8 *pos = ies, *end = ies + len;
	int ie_oui;

	while (pos < end) {
		pos = atbm_ieee80211_find_ie(ATBM_WLAN_EID_VENDOR_SPECIFIC, pos,
				       end - pos);
		if (!pos)
			return NULL;

		ie = (struct atbm_ieee80211_vendor_ie *)pos;

		/* make sure we can access ie->len */
		BUILD_BUG_ON(offsetof(struct atbm_ieee80211_vendor_ie, len) != 1);

		if (ie->len < sizeof(*ie))
			goto cont;

		ie_oui = ie->oui[0] << 16 | ie->oui[1] << 8 | ie->oui[2];
		if (ie_oui == oui && ie->oui_type == oui_type)
			return pos;
cont:
		pos += 2 + ie->len;
	}
	return NULL;
}

static inline u8* atbm_ieee80211_find_p2p_ie(const u8 *ie_start,size_t ie_len)
{
	if((ie_start == NULL)||(ie_len == 0))
		return NULL;
	return (u8*)atbm_ieee80211_find_vendor_ie(ATBM_OUI_WFA,ATBM_P2P_OUI_TYPE,ie_start,ie_len);
}

static inline u8* atbm_ieee80211_find_p2p_attr(u8* attr_start,ssize_t attr_len,u8 attr_id)
{
	if((attr_start == NULL)||(attr_len == 0))
		return NULL;
	// 3 = 1(Attribute ID) + 2(Length)
	while (attr_len > 2 && attr_start[0] != attr_id) {
		attr_len -= ATBM_WPA_GET_LE16((const u8*)(&attr_start[1])) + 3;
		attr_start += ATBM_WPA_GET_LE16((const u8*)(&attr_start[1])) + 3;
	}

	if(attr_len<3)
		return NULL;
	if (attr_len < 3 + ATBM_WPA_GET_LE16((const u8*)(&attr_start[1])))
		return NULL;

	return attr_start;
}

static inline int ieee80211_p2p_action_check(u8* data,ssize_t data_len)
{
	#define RETURN_ERR do{res = -1;goto action_check_end;}while(0)
	int res = 0;
	u8* p2p_data = data;
	ssize_t p2p_data_len = data_len;
	u32 oui_wfa = 0;
	
	if(p2p_data[0] != 9/*vendor spec*/)
		RETURN_ERR;

	if(p2p_data_len<3)
		RETURN_ERR;
	
	p2p_data++;
	p2p_data_len--;

	oui_wfa = (p2p_data[0] << 16) | (p2p_data[1] << 8) | p2p_data[2];

	if(oui_wfa != ATBM_OUI_WFA)
		RETURN_ERR;

	p2p_data += 3;
	p2p_data_len -= 3;
	if (p2p_data_len < 1)
		RETURN_ERR;

	if(p2p_data[0] != ATBM_P2P_OUI_TYPE)
		RETURN_ERR;

	p2p_data++;
	p2p_data_len--;

	if(p2p_data_len<1)
		RETURN_ERR;

	res = data_len-p2p_data_len;
action_check_end:
	return res;
}

#ifndef do_posix_clock_monotonic_gettime
#define do_posix_clock_monotonic_gettime(ts) ktime_get_ts(ts)
#endif
static inline bool atbm_accsii_to_hex(char pos,char *res)
{
	if((pos>='0')&&(pos<='9')){
		*res = pos-'0';
		return true;
	}else if((pos>='a')&&(pos<='f')){
		*res = pos - 'a'+0x0a;
		return true;
	}else if((pos>='A')&&(pos<='F')){
		*res = pos - 'A'+0x0a;
		return true;
	}

	return false;
}

static inline bool atbm_accsii_to_int(const char *pos,int len,int *res)
{
	int res_val = 0;
	int index = 0;
	bool neg = false;
	const char *accsii = pos;

	if((len == 0) || (len>10) || (len<0))
		return false;
	
	neg   = pos[0] == '-'  ? true:false;
	index = neg    == true ? 1:0;

	if((neg==true)&&(len == 1))
		return false;
	
	for(;index<len;index++){
		
		if((accsii[index] < '0') || (accsii[index] > '9')){
			return false;
		}

		res_val = res_val*10;

		res_val += accsii[index]-'0';
	}

	res_val = neg == true?0-res_val:res_val;

	*res = res_val;

	return true;
}
static inline void atbm_common_hash_list_init(struct hlist_head *hlist,u8 size)
{
	u8 index = 0;
	
	for(index = 0;index<size;index++){
		INIT_HLIST_HEAD(&hlist[index]);
	}
}

static inline unsigned int atbm_hash_index(const char *string,unsigned int len,unsigned int hash_bit)
{
	#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 8, 0))
	unsigned int hash = full_name_hash(NULL,string,len);
	#else
	unsigned int hash = full_name_hash(string,len);
	#endif

	return hash_32(hash, hash_bit);
}

static inline struct hlist_head *atbm_hash_list(const char *string,unsigned int len,struct hlist_head *hlist_table,unsigned int hash_bit)
{
	unsigned int hash = atbm_hash_index(string,len,hash_bit);

	return &hlist_table[hash];
}
static inline u8 ieee80211_rssi_weight(s8 signal)
{
	u8 weight = 0;

	if(signal <= -75)
		weight = 0;
	else if((signal>-75)&&(signal<= -65))
		weight = 1;
	else if((signal>-65)&&(signal<= -50))
		weight = 2;
	else if(signal > -50)
		weight = 4;
	else 
		weight = 0;

	return weight;
}
static inline struct ieee80211_rx_status *IEEE80211_SKB_RXCB(struct sk_buff *skb)
{
	return (struct ieee80211_rx_status *)skb->cb;
}

#define ATBM_SPACE	' '
#define ATBM_LINEF	'\n'
#define ATBM_ENTER	'\r'
#define ATBM_TAIL	'\0'
#define ATBM_EQUAL	'='
#define ATBM_UNUSED	'#'
#define ATBM_SOH	1
#define ATBM_EOT	4
#define ATBM_STX	2
#define ATBM_ETX	3
#define ATBM_SPACE_STR	" "
#define ATBM_LINEF_STR	"\n"

#define ATBM_COMMON_HASHBITS    4
#define ATBM_COMMON_HASHENTRIES (1 << ATBM_COMMON_HASHBITS)

#define ATBM_MAX_SCAN_IE							1
#define ATBM_MAX_SCAN_SSID							2
#define ATBM_MAX_SCAN_MAC_FILTER					8
#define ATBM_MAX_SCAN_PRIVATE_IE_LEN				(255-4)
#define ATBM_MAX_SCAN_CHANNEL						(14+4)

extern u32 atbm_printk_mask;
#define ATBM_PRINTK_MASK_ERR			BIT(0)
#define ATBM_PRINTK_MASK_WARN			BIT(1)
#define ATBM_PRINTK_MASK_INIT			BIT(2)
#define ATBM_PRINTK_MASK_EXIT			BIT(3)
#define ATBM_PRINTK_MASK_BUS			BIT(4)
#define ATBM_PRINTK_MASK_SCAN			BIT(5)
#define ATBM_PRINTK_MASK_P2P			BIT(6)
#define ATBM_PRINTK_MASK_MGMT			BIT(7)
#define ATBM_PRINTK_MASK_LMAC			BIT(8)
#define ATBM_PRINTK_MASK_AGG			BIT(9)
#define ATBM_PRINTK_MASK_AP				BIT(10)
#define ATBM_PRINTK_MASK_STA			BIT(11)
#define ATBM_PRINTK_MASK_SMARTCONFIG	BIT(12)
#define ATBM_PRINTK_MASK_WEXT			BIT(13)
#define ATBM_PRINTK_MASK_TX				BIT(14)
#define ATBM_PRINTK_MASK_RX				BIT(15)
#define ATBM_PRINTK_MASK_PM				BIT(16)
#define ATBM_PRINTK_MASK_PLATFROM		BIT(17)
#define ATBM_PRINTK_MASK_BH				BIT(18)
#define ATBM_PRINTK_MASK_CFG80211		BIT(19)
#define ATBM_PRINTK_MASK_DEBUG			BIT(20)

#define ATBM_PRINTK_DEFAULT_MASK	(ATBM_PRINTK_MASK_ERR|ATBM_PRINTK_MASK_WARN|ATBM_PRINTK_MASK_INIT| \
									ATBM_PRINTK_MASK_EXIT|ATBM_PRINTK_MASK_SCAN|ATBM_PRINTK_MASK_LMAC|ATBM_PRINTK_MASK_PM)
#define ATBM_PRINTK_ALL ((u32)(-1))
#define ATBM_PRINTK_CLEAR		(0)
#define ATBM_TAG "[atbm_log]:"
#define atbm_printk(_level,fmt,arg...) 	do {if(atbm_printk_mask&(_level)) printk(KERN_ERR ATBM_TAG fmt,##arg);}while(0)


/*
*atbm printk
*/
#define atbm_printk_err(...) 		atbm_printk(ATBM_PRINTK_MASK_ERR,__VA_ARGS__)
#define atbm_printk_warn(...)		atbm_printk(ATBM_PRINTK_MASK_WARN,__VA_ARGS__)
#define atbm_printk_init(...)		atbm_printk(ATBM_PRINTK_MASK_INIT,__VA_ARGS__)
#define atbm_printk_exit(...)		atbm_printk(ATBM_PRINTK_MASK_EXIT,__VA_ARGS__)
#define atbm_printk_bus(...)		atbm_printk(ATBM_PRINTK_MASK_BUS,__VA_ARGS__)
#define atbm_printk_scan(...)		atbm_printk(ATBM_PRINTK_MASK_SCAN,__VA_ARGS__)
#define atbm_printk_p2p(...)		atbm_printk(ATBM_PRINTK_MASK_P2P,__VA_ARGS__)
#define atbm_printk_mgmt(...)		atbm_printk(ATBM_PRINTK_MASK_MGMT,__VA_ARGS__)
#define atbm_printk_lmac(...)		atbm_printk(ATBM_PRINTK_MASK_LMAC,__VA_ARGS__)
#define atbm_printk_agg(...)		atbm_printk(ATBM_PRINTK_MASK_AGG,__VA_ARGS__)
#define atbm_printk_ap(...)			atbm_printk(ATBM_PRINTK_MASK_AP,__VA_ARGS__)
#define atbm_printk_sta(...)		atbm_printk(ATBM_PRINTK_MASK_STA,__VA_ARGS__)
#define atbm_printk_smt(...)		atbm_printk(ATBM_PRINTK_MASK_SMARTCONFIG,__VA_ARGS__)
#define atbm_printk_wext(...)		atbm_printk(ATBM_PRINTK_MASK_WEXT,__VA_ARGS__)
#define atbm_printk_tx(...)			atbm_printk(ATBM_PRINTK_MASK_TX,__VA_ARGS__)
#define atbm_printk_rx(...)			atbm_printk(ATBM_PRINTK_MASK_RX,__VA_ARGS__)
#define atbm_printk_pm(...)			atbm_printk(ATBM_PRINTK_MASK_PM,__VA_ARGS__)
#define atbm_printk_platform(...)	atbm_printk(ATBM_PRINTK_MASK_PLATFROM,__VA_ARGS__)
#define atbm_printk_bh(...)			atbm_printk(ATBM_PRINTK_MASK_BH,__VA_ARGS__)
#define atbm_printk_cfg(...)		atbm_printk(ATBM_PRINTK_MASK_CFG80211,__VA_ARGS__)
#define atbm_printk_debug(...)		atbm_printk(ATBM_PRINTK_MASK_DEBUG,__VA_ARGS__)
#define atbm_printk_always(fmt,arg...)		printk(KERN_ERR ATBM_TAG fmt,##arg)


#define ATBM_MAC2STR(a) (a)[0], (a)[1], (a)[2], (a)[3], (a)[4], (a)[5]
#define ATBM_MACSTR "%02x:%02x:%02x:%02x:%02x:%02x"
static inline const char* atbm_skip_space(const char *target,ssize_t len)
{
	const char* pos_end = target+len;

	if((len <= 0)||(target == NULL)){
		return NULL;
	}
	while((*target == ATBM_SPACE)||(*target == ATBM_LINEF)||(*target == ATBM_ENTER)){
		target++;
		if(target == pos_end){
			break;
		}
	}
	return (target == pos_end? NULL:target);
}

#define ieee80211_chw_is_ht40(chtype) (((chtype) == NL80211_CHAN_HT40PLUS) || ((chtype) == NL80211_CHAN_HT40MINUS))
#define LIGHT	"\e[1m"
#define NORMAL	"\e[0m"
#define ENTER	"\n"
#define highlight_debug(fmt,arg...)			\
	printk(KERN_ERR LIGHT fmt NORMAL ENTER,##arg)

#ifdef MODULE
#define atbm_module_parent			(&THIS_MODULE->mkobj.kobj)
#else
#define atbm_module_parent			(NULL)
#endif
/*
*atbm timer function
*/
struct atbm_timer_list {
	struct timer_list timer;
	void (*function)(unsigned long data);
	unsigned long data;
	unsigned long expires;
};

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 14, 0))
static inline void atbm_timer_handle(struct timer_list *in_timer)
#else
static inline void atbm_timer_handle(unsigned long data)
#endif
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 14, 0))
	struct atbm_timer_list *atbm_timer = from_timer(atbm_timer, in_timer, timer);
#else
	struct atbm_timer_list *atbm_timer = (struct atbm_timer_list *)data;
#endif
	BUG_ON(atbm_timer->function == NULL);
	atbm_timer->function(atbm_timer->data);
}

static inline void atbm_init_timer(struct atbm_timer_list *atbm_timer)
{
	atbm_timer->expires = 0;
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 14, 0))
	timer_setup(&atbm_timer->timer, atbm_timer_handle, 0);
#else
	/* setup_timer(ptimer, pfunc,(u32)cntx);	 */
	atbm_timer->timer.function = atbm_timer_handle;
	atbm_timer->timer.data = (unsigned long)atbm_timer;
	init_timer(&atbm_timer->timer);
#endif
}

static inline void atbm_setup_timer(struct atbm_timer_list *atbm_timer,
				   void (*function)(unsigned long data),unsigned long data)
{
	atbm_timer->expires = 0;
	atbm_timer->function = function;
	atbm_timer->data = data;
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 14, 0))
	timer_setup(&atbm_timer->timer, atbm_timer_handle, 0);
#else
	
	atbm_timer->timer.function = atbm_timer_handle;
	atbm_timer->timer.data = (unsigned long)atbm_timer;
	init_timer(&atbm_timer->timer);
#endif
}
static inline int atbm_del_timer_sync(struct atbm_timer_list *atbm_timer)
{
	return del_timer_sync(&atbm_timer->timer);
}
static inline int atbm_mod_timer(struct atbm_timer_list *atbm_timer, unsigned long expires)
{
	int ret = 0;
	ret =  mod_timer(&atbm_timer->timer,expires);
	atbm_timer->expires = atbm_timer->timer.expires;

	return ret;
}

static inline void atbm_add_timer(struct atbm_timer_list *atbm_timer)
{
	add_timer(&atbm_timer->timer);
}

static inline int atbm_del_timer(struct atbm_timer_list *atbm_timer)
{
	return del_timer(&atbm_timer->timer);
}
static inline int atbm_timer_pending(struct atbm_timer_list *atbm_timer)
{
	return timer_pending(&atbm_timer->timer);
}

#endif /* MAC80211_H */
