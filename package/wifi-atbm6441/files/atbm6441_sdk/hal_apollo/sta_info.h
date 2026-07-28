/*
 * Copyright 2002-2005, Devicescape Software, Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef STA_INFO_H
#define STA_INFO_H

#ifdef LINUX_OS
#include <linux/list.h>
#include <linux/types.h>
#include <linux/if_ether.h>
#include <linux/workqueue.h>
#include <linux/average.h>
#endif
/**
 * enum ieee80211_sta_info_flags - Stations flags
 *
 * These flags are used with &struct sta_info's @flags member, but
 * only indirectly with set_sta_flag() and friends.
 *
 * @WLAN_STA_AUTH: Station is authenticated.
 * @WLAN_STA_ASSOC: Station is associated.
 * @WLAN_STA_PS_STA: Station is in power-save mode
 * @WLAN_STA_AUTHORIZED: Station is authorized to send/receive traffic.
 *	This bit is always checked so needs to be enabled for all stations
 *	when virtual port control is not in use.
 * @WLAN_STA_SHORT_PREAMBLE: Station is capable of receiving short-preamble
 *	frames.
 * @WLAN_STA_ASSOC_AP: We're associated to that station, it is an AP.
 * @WLAN_STA_WME: Station is a QoS-STA.
 * @WLAN_STA_WDS: Station is one of our WDS peers.
 * @WLAN_STA_CLEAR_PS_FILT: Clear PS filter in hardware (using the
 *	IEEE80211_TX_CTL_CLEAR_PS_FILT control flag) when the next
 *	frame to this station is transmitted.
 * @WLAN_STA_MFP: Management frame protection is used with this STA.
 * @WLAN_STA_BLOCK_BA: Used to deny ADDBA requests (both TX and RX)
 *	during suspend/resume and station removal.
 * @WLAN_STA_PS_DRIVER: driver requires keeping this station in
 *	power-save mode logically to flush frames that might still
 *	be in the queues
 * @WLAN_STA_PSPOLL: Station sent PS-poll while driver was keeping
 *	station in power-save mode, reply when the driver unblocks.
 * @WLAN_STA_TDLS_PEER: Station is a TDLS peer.
 * @WLAN_STA_TDLS_PEER_AUTH: This TDLS peer is authorized to send direct
 *	packets. This means the link is enabled.
 * @WLAN_STA_UAPSD: Station requested unscheduled SP while driver was
 *	keeping station in power-save mode, reply when the driver
 *	unblocks the station.
 * @WLAN_STA_SP: Station is in a service period, so don't try to
 *	reply to other uAPSD trigger frames or PS-Poll.
 */
enum ieee80211_sta_info_flags {
	WLAN_STA_AUTH,
	WLAN_STA_ASSOC,
	WLAN_STA_PS_STA,
	WLAN_STA_AUTHORIZED,
	WLAN_STA_SHORT_PREAMBLE,
	WLAN_STA_ASSOC_AP,
	WLAN_STA_WME,
	WLAN_STA_WDS,
	WLAN_STA_CLEAR_PS_FILT,
	WLAN_STA_MFP,
	WLAN_STA_BLOCK_BA,
	WLAN_STA_PS_DRIVER,
	WLAN_STA_PSPOLL,
	WLAN_STA_TDLS_PEER,
	WLAN_STA_TDLS_PEER_AUTH,
	WLAN_STA_UAPSD,
	WLAN_STA_SP,
	WLAN_STA_ASSOCED,
	WLAN_STA_AUTH_STATUS,
	WLAN_STA_SHORT_SLOT,
	WLAN_STA_DEAUTHENNING,
	WLAN_STA_DEAUTHENED,
	WLAN_STA_PAIRWISE_KEY_SET,
	WLAN_STA_WPA_RSN,
	WLAN_STA_WPS,
	WLAN_STA_40M_CH,
	WLAN_STA_40M_CH_SEND_20M,
	WLAN_STA_HANDSHAKE4OF4_SENDING,
	WLAN_STA_HANDSHAKE4OF4_SUCCESS,
	WLAN_STA_RESTART,
};

#define STA_TID_NUM 16
#define ADDBA_RESP_INTERVAL HZ
#define HT_AGG_MAX_RETRIES		0x3

#define HT_AGG_STATE_DRV_READY		0
#define HT_AGG_STATE_RESPONSE_RECEIVED	1
#define HT_AGG_STATE_OPERATIONAL	2
#define HT_AGG_STATE_STOPPING		3
#define HT_AGG_STATE_WANT_START		4
#define HT_AGG_STATE_WANT_STOP		5
#define NUM_RX_DATA_QUEUES	16

/**
 * struct tid_ampdu_tx - TID aggregation information (Tx).
 *
 * @rcu_head: rcu head for freeing structure
 * @addba_resp_timer: timer for peer's response to addba request
 * @pending: pending frames queue -- use sta's spinlock to protect
 * @dialog_token: dialog token for aggregation session
 * @timeout: session timeout value to be filled in ADDBA requests
 * @state: session state (see above)
 * @stop_initiator: initiator of a session stop
 * @tx_stop: TX DelBA frame when stopping
 * @buf_size: reorder buffer size at receiver
 * @failed_bar_ssn: ssn of the last failed BAR tx attempt
 * @bar_pending: BAR needs to be re-sent
 *
 * This structure's lifetime is managed by RCU, assignments to
 * the array holding it must hold the aggregation mutex.
 *
 * The TX path can access it under RCU lock-free if, and
 * only if, the state has the flag %HT_AGG_STATE_OPERATIONAL
 * set. Otherwise, the TX path must also acquire the spinlock
 * and re-check the state, see comments in the tx code
 * touching it.
 */
struct tid_ampdu_tx {
	struct rcu_head rcu_head;
	struct atbm_timer_list addba_resp_timer;
	struct sk_buff_head pending;
	unsigned long state;
	u16 timeout;
	u8 dialog_token;
	u8 stop_initiator;
	bool tx_stop;
	u8 buf_size;

	u16 failed_bar_ssn;
	bool bar_pending;
};

/**
 * struct tid_ampdu_rx - TID aggregation information (Rx).
 *
 * @reorder_buf: buffer to reorder incoming aggregated MPDUs
 * @reorder_time: jiffies when skb was added
 * @session_timer: check if peer keeps Tx-ing on the TID (by timeout value)
 * @reorder_timer: releases expired frames from the reorder buffer.
 * @head_seq_num: head sequence number in reordering buffer.
 * @stored_mpdu_num: number of MPDUs in reordering buffer
 * @ssn: Starting Sequence Number expected to be aggregated.
 * @buf_size: buffer size for incoming A-MPDUs
 * @timeout: reset timer value (in TUs).
 * @dialog_token: dialog token for aggregation session
 * @rcu_head: RCU head used for freeing this struct
 * @reorder_lock: serializes access to reorder buffer, see below.
 *
 * This structure's lifetime is managed by RCU, assignments to
 * the array holding it must hold the aggregation mutex.
 *
 * The @reorder_lock is used to protect the members of this
 * struct, except for @timeout, @buf_size and @dialog_token,
 * which are constant across the lifetime of the struct (the
 * dialog token being used only for debugging).
 */
struct tid_ampdu_rx {
	struct rcu_head rcu_head;
	spinlock_t reorder_lock;
	struct sk_buff **reorder_buf;
	unsigned long *reorder_time;
	struct atbm_timer_list session_timer;
	struct atbm_timer_list reorder_timer;
	u16 head_seq_num;
	u16 stored_mpdu_num;
	u16 ssn;
	u16 buf_size;
	u16 timeout;
	u8 dialog_token;
};

/**
 * struct sta_ampdu_mlme - STA aggregation information.
 *
 * @tid_rx: aggregation info for Rx per TID -- RCU protected
 * @tid_tx: aggregation info for Tx per TID
 * @tid_start_tx: sessions where start was requested
 * @addba_req_num: number of times addBA request has been sent.
 * @dialog_token_allocator: dialog token enumerator for each new session;
 * @work: work struct for starting/stopping aggregation
 * @tid_rx_timer_expired: bitmap indicating on which TIDs the
 *	RX timer expired until the work for it runs
 * @tid_rx_stop_requested:  bitmap indicating which BA sessions per TID the
 *	driver requested to close until the work for it runs
 * @mtx: mutex to protect all TX data (except non-NULL assignments
 *	to tid_tx[idx], which are protected by the sta spinlock)
 */
struct sta_ampdu_mlme {
	struct mutex mtx;
	/* rx */
	struct tid_ampdu_rx __rcu *tid_rx[STA_TID_NUM];
	unsigned long tid_rx_timer_expired[BITS_TO_LONGS(STA_TID_NUM)];
	unsigned long tid_rx_stop_requested[BITS_TO_LONGS(STA_TID_NUM)];
	/* tx */
	struct work_struct work;
	struct tid_ampdu_tx __rcu *tid_tx[STA_TID_NUM];
	struct tid_ampdu_tx *tid_start_tx[STA_TID_NUM];
	u8 addba_req_num[STA_TID_NUM];
	u8 dialog_token_allocator;
};
#define ATBM_WLAN_CIPHER_SUITE_WEP40	0x01
#define ATBM_WLAN_CIPHER_SUITE_TKIP		0x02
/* reserved: 				0x000FAC03 */
#define ATBM_WLAN_CIPHER_SUITE_CCMP		0x04
#define ATBM_WLAN_CIPHER_SUITE_WEP104	0x05
#define ATBM_WLAN_CIPHER_SUITE_AES_CMAC	0x06
#define ATBM_WLAN_CIPHER_SUITE_GCMP		0x08
#define ATBM_WLAN_CIPHER_SUITE_GCMP_256	0x09
#define ATBM_WLAN_CIPHER_SUITE_CCMP_256	0x0A
#if (LINUX_VERSION_CODE < KERNEL_VERSION(4, 19, 0))
#define WLAN_CIPHER_SUITE_BIP_GMAC_128	0x0B
#define WLAN_CIPHER_SUITE_BIP_GMAC_256	0x0C
#define WLAN_CIPHER_SUITE_BIP_CMAC_256	0x0D

#define WLAN_CIPHER_SUITE_SMS4		0x00147201
#endif
enum ieee80211_enc_type{
	IEEE80211_ENC_TYPE = 1,
	IEEE80211_ENC_WEP,
	IEEE80211_ENC_TKIP,
	IEEE80211_ENC_AES,
	IEEE80211_ENC_AES_CMAC,
	IEEE80211_ENC_WAPI,
};

struct ieee80211_key {
	unsigned int flags;
	enum ieee80211_enc_type key_type;
	struct ieee80211_key_conf conf;
};

/**
 * struct sta_info - STA information
 *
 * This structure collects information about a station that
 * mac80211 is communicating with.
 *
 * @list: global linked list entry
 * @hnext: hash table linked list pointer
 * @local: pointer to the global information
 * @sdata: virtual interface this station belongs to
 * @ptk: peer key negotiated with this station, if any
 * @gtk: group keys negotiated with this station, if any
 * @rate_ctrl: rate control algorithm reference
 * @rate_ctrl_priv: rate control private per-STA pointer
 * @last_tx_rate: rate used for last transmit, to report to userspace as
 *	"the" transmit rate
 * @last_rx_rate_idx: rx status rate index of the last data packet
 * @last_rx_rate_flag: rx status flag of the last data packet
 * @lock: used for locking all fields that require locking, see comments
 *	in the header file.
 * @drv_unblock_wk: used for driver PS unblocking
 * @listen_interval: listen interval of this station, when we're acting as AP
 * @_flags: STA flags, see &enum ieee80211_sta_info_flags, do not use directly
 * @ps_tx_buf: buffers (per AC) of frames to transmit to this station
 *	when it leaves power saving state or polls
 * @tx_filtered: buffers (per AC) of frames we already tried to
 *	transmit but were filtered by hardware due to STA having
 *	entered power saving state, these are also delivered to
 *	the station when it leaves powersave or polls for frames
 * @driver_buffered_tids: bitmap of TIDs the driver has data buffered on
 * @rx_packets: Number of MSDUs received from this STA
 * @rx_bytes: Number of bytes received from this STA
 * @wep_weak_iv_count: number of weak WEP IVs received from this station
 * @last_rx: time (in jiffies) when last frame was received from this STA
 * @last_connected: time (in seconds) when a station got connected
 * @num_duplicates: number of duplicate frames received from this STA
 * @rx_fragments: number of received MPDUs
 * @rx_dropped: number of dropped MPDUs from this STA
 * @last_signal: signal of last received frame from this STA
 * @avg_signal: moving average of signal of received frames from this STA
 * @last_seq_ctrl: last received seq/frag number from this STA (per RX queue)
 * @tx_filtered_count: number of frames the hardware filtered for this STA
 * @tx_retry_failed: number of frames that failed retry
 * @tx_retry_count: total number of retries for frames to this STA
 * @fail_avg: moving percentage of failed MSDUs
 * @tx_packets: number of RX/TX MSDUs
 * @tx_bytes: number of bytes transmitted to this STA
 * @tx_fragments: number of transmitted MPDUs
 * @tid_seq: per-TID sequence numbers for sending to this STA
 * @ampdu_mlme: A-MPDU state machine state
 * @timer_to_tid: identity mapping to ID timers
 * @llid: Local link ID
 * @plid: Peer link ID
 * @reason: Cancel reason on PLINK_HOLDING state
 * @plink_retries: Retries in establishment
 * @ignore_plink_timer: ignore the peer-link timer (used internally)
 * @plink_state: peer link state
 * @plink_timeout: timeout of peer link
 * @plink_timer: peer link watch timer
 * @plink_timer_was_running: used by suspend/resume to restore timers
 * @debugfs: debug filesystem info
 * @dead: set to true when sta is unlinked
 * @uploaded: set to true when sta is uploaded to the driver
 * @lost_packets: number of consecutive lost packets
 * @dummy: indicate a dummy station created for receiving
 *	EAP frames before association
 * @sta: station information we share with the driver
 */
#define STA_11B_MODE BIT(0)
#define STA_11G_MODE BIT(1)
#define STA_11N_MODE BIT(2)
struct sta_info {
	/* General information, mostly static */
	struct list_head list;
	struct sta_info __rcu *hnext;
	struct atbm_vif *vif;
	struct atbm_common *hw_priv;
	spinlock_t lock;

	bool dead;

	bool uploaded;

	/* use the accessors defined below */
	unsigned long _flags;
	__le16 last_seq_ctrl[NUM_RX_DATA_QUEUES + 1];
	u16 tid_seq[IEEE80211_QOS_CTL_TID_MASK + 1];
	/*
	 * Aggregation information, locked with lock.
	 */
	struct sta_ampdu_mlme ampdu_mlme;
	u8 timer_to_tid[STA_TID_NUM];
	/* should be right in front of sta to be in the same cache line */
	bool dummy;
	bool enc;
	bool wmm;
	u8 	mic_len;
	u8  bgnMode;//BIT0 11b;BIT1 11g ;BIT2 11n
	bool shortGI;
	/* keep last! */
	struct ieee80211_key key;
	struct ieee80211_sta sta;
};

static inline void set_sta_flag(struct sta_info *sta,
				enum ieee80211_sta_info_flags flag)
{
	set_bit(flag, &sta->_flags);
}

static inline void clear_sta_flag(struct sta_info *sta,
				  enum ieee80211_sta_info_flags flag)
{
	clear_bit(flag, &sta->_flags);
}

static inline int test_sta_flag(struct sta_info *sta,
				enum ieee80211_sta_info_flags flag)
{
	return test_bit(flag, &sta->_flags);
}

static inline int test_and_clear_sta_flag(struct sta_info *sta,
					  enum ieee80211_sta_info_flags flag)
{
	return test_and_clear_bit(flag, &sta->_flags);
}
#define STA_HASH_SIZE 256
#define STA_HASH(sta) (sta[5])


/* Maximum number of frames to buffer per power saving station per AC */
#define STA_MAX_TX_BUFFER	64

/* Minimum buffered frame expiry time. If STA uses listen interval that is
 * smaller than this value, the minimum value here is used instead. */
#define STA_TX_BUFFER_EXPIRE (5 * HZ)

/* How often station data is cleaned up (e.g., expiration of buffered frames)
 */
#define STA_INFO_CLEANUP_INTERVAL (4 * HZ)

/*
 * Get a STA info, must be under RCU read lock.
 */
struct sta_info *sta_info_get(struct atbm_vif *priv,
			      const u8 *addr);

struct sta_info *sta_info_get_rx(struct atbm_vif *priv,
			      const u8 *addr);
/*
 * Create a new STA info, caller owns returned structure
 * until sta_info_insert().
 */
struct sta_info *sta_info_alloc(struct atbm_vif *vif,
				u8 *addr, gfp_t gfp);
int  __sta_info_destroy(struct sta_info *sta);
/*
 * Insert STA info into hash table/list, returns zero or a
 * -EEXIST if (if the same MAC address is already present).
 *
 * Calling the non-rcu version makes the caller relinquish,
 * the _rcu version calls read_lock_rcu() and must be called
 * without it held.
 */
int sta_info_insert(struct sta_info *sta);
int sta_info_insert_rcu(struct sta_info *sta) __acquires(RCU);

void sta_info_init(struct atbm_common *hw_priv);
void sta_info_stop(struct atbm_common *hw_priv);
int sta_info_flush(struct atbm_common *hw_priv,
		   struct atbm_vif *vif);

#endif /* STA_INFO_H */
