/*
 * Common private data for altobeam APOLLO drivers
 *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 *  Based on apollo  Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * Based on the mac80211 Prism54 code, which is
 * Copyright (c) 2006, Michael Wu <flamingice@sourmilk.net>
 *
 * Based on the islsm (softmac prism54) driver, which is:
 * Copyright 2004-2006 Jean-Baptiste Note <jbnote@gmail.com>, et al.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef ATBM_APOLLO_H
#define ATBM_APOLLO_H
#ifdef LINUX_OS
#include <linux/interrupt.h>
#include <linux/wait.h>
#include <linux/mutex.h>
#include <linux/workqueue.h>
#include <linux/sched.h>
#include <linux/atomic.h>
#include <net/atbm_mac80211.h>
#endif
#include "atbm_os.h"

#include "apollo_plat.h"
#include "sta_info.h"

#ifdef LINUX_OS
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0))
#include <uapi/linux/sched/types.h>
#endif
#endif

#define ATBM_WIFI_MAX_VIFS			(1)
#define ATBM_WIFI_GENERIC_IF_ID		(0)
#define ATBM_WIFI_HOST_VIF0_11N_THROTTLE	(ATBM_WIFI_MAX_QUEUE_SZ*3/4-1)
#define ATBM_WIFI_HOST_VIF1_11N_THROTTLE	(ATBM_WIFI_MAX_QUEUE_SZ*3/4-1)
#define ATBM_WIFI_HOST_VIF0_11BG_THROTTLE	(63)
#define ATBM_WIFI_HOST_VIF1_11BG_THROTTLE	(63)


#define ATBM_WIFI_MAX_QUEUE_SZ		(256)

#define ATBM_QUEUE_DEFAULT_CAP		(ATBM_WIFI_MAX_QUEUE_SZ>>4)
#define ATBM_QUEUE_SINGLE_CAP		(ATBM_WIFI_MAX_QUEUE_SZ*7/8)
#define ATBM_QUEUE_COMB_CAP			(ATBM_WIFI_MAX_QUEUE_SZ/2-8)


#define ST_PAYLOAD_BUF_SZ			(256)

#define IEEE80211_FCTL_WEP      0x4000
#define IEEE80211_QOS_DATAGRP   0x0080
#define WSM_KEY_MAX_IDX		20

#include "wsm.h"
#include "fwio.h"
#include "pm.h"
//#ifdef CONFIG_ATBM_APOLLO_TESTMODE
#include "atbm_testmode.h"
//#endif /*CONFIG_ATBM_APOLLO_TESTMODE*/

/* extern */ struct sbus_ops;
/* #define ROC_DEBUG */

/* hidden ssid is only supported when separate probe resp IE
   configuration is supported */

#define txrx_printk(...) atbm_printk_always(__VA_ARGS__)


#define ATBM_APOLLO_MAX_CTRL_FRAME_LEN	(0x1000)

#define ATBMWIFI_MAX_STA_IN_AP_MODE	(14)
#define WLAN_LINK_ID_MAX		(ATBMWIFI_MAX_STA_IN_AP_MODE + 3)

#define ATBM_APOLLO_MAX_STA_IN_AP_MODE		 ATBMWIFI_MAX_STA_IN_AP_MODE
#define ATBM_APOLLO_MAX_REQUEUE_ATTEMPTS	(5)
#define ATBM_APOLLO_LINK_ID_UNMAPPED		(15)

#define ATBM_APOLLO_MAX_TID			(8)

#define ATBM_APOLLO_TX_BLOCK_ACK_ENABLED_FOR_ALL_TID         (0xff)
#define ATBM_APOLLO_RX_BLOCK_ACK_ENABLED_FOR_ALL_TID         (0xff)
#define ATBM_APOLLO_RX_BLOCK_ACK_ENABLED_FOR_BE_TID \
	(ATBM_APOLLO_TX_BLOCK_ACK_ENABLED_FOR_ALL_TID & 0x01)
#define ATBM_APOLLO_TX_BLOCK_ACK_DISABLED_FOR_ALL_TID	(0)
#define ATBM_APOLLO_RX_BLOCK_ACK_DISABLED_FOR_ALL_TID	(0)

#define ATBM_APOLLO_BLOCK_ACK_CNT		(30)
#define ATBM_APOLLO_BLOCK_ACK_THLD		(800)
#define ATBM_APOLLO_BLOCK_ACK_HIST		(3)
#define ATBM_APOLLO_BLOCK_ACK_INTERVAL	(1 * HZ / ATBM_APOLLO_BLOCK_ACK_HIST)
#define ATBM_WIFI_ALL_IFS			(-1)

#define IEEE80211_FCTL_WEP      0x4000
#define IEEE80211_QOS_DATAGRP   0x0080
#ifdef CONFIG_ATBM_APOLLO_TESTMODE
#define ATBM_APOLLO_SCAN_MEASUREMENT_PASSIVE (0)
#define ATBM_APOLLO_SCAN_MEASUREMENT_ACTIVE  (1)
#endif

#ifdef CONFIG_ATBM_SDIO_ATCMD
#define ATBM_AT_CMD_MAX_SW_CACHE			8	//must 2 ^ n
#endif

/* Please keep order */
enum atbm_join_status {
	ATBM_APOLLO_JOIN_STATUS_PASSIVE = 0,	
	ATBM_APOLLO_JOIN_STATUS_STA_LISTEN,
	ATBM_APOLLO_JOIN_STATUS_MONITOR,
	ATBM_APOLLO_JOIN_STATUS_IBSS,
	ATBM_APOLLO_JOIN_STATUS_STA,
	ATBM_APOLLO_JOIN_STATUS_AP,
	ATBM_APOLLO_JOIN_STATUS_SIMPLE_MONITOR,
};

enum atbm_link_status {
	ATBM_APOLLO_LINK_OFF,
	ATBM_APOLLO_LINK_RESERVE,
	ATBM_APOLLO_LINK_SOFT,
	ATBM_APOLLO_LINK_HARD,
	ATBM_APOLLO_LINK_RESET,
	ATBM_APOLLO_LINK_RESET_REMAP,
};

enum atbm_bss_loss_status {
	ATBM_APOLLO_BSS_LOSS_NONE,
	ATBM_APOLLO_BSS_LOSS_CHECKING,
	ATBM_APOLLO_BSS_LOSS_CONFIRMING,
	ATBM_APOLLO_BSS_LOSS_CONFIRMED,
};


#ifdef CONFIG_ATBM_SDIO_ATCMD
struct at_cmd_direct{
	u32 len;
	u8 cmd[1500];	
};
#endif

struct atbm_common {
	struct device			    *pdev;
	struct atbm_vif				__rcu *vif_list[ATBM_WIFI_MAX_VIFS];
	struct workqueue_struct		*workqueue;
	struct sk_buff_head			rx_frame_queue;
	struct sk_buff_head			tx_frame_queue;
	struct sk_buff_head			rx_frame_free;
	struct mutex			    conf_mutex;
	bool 						bh_error;
	const struct sbus_ops		*sbus_ops;
	struct sbus_priv		    *sbus_priv;
	int 						init_done;
	int 						close_driver;
	int							hw_type;
	int							hw_revision;
	int							fw_revision;
	u8 							mac_addr[ETH_ALEN];
#ifdef CONFIG_PM
	struct atbm_pm_state		pm_state;
#endif
#ifdef SDIO_BUS
	bool				hard_irq;
#endif
	struct task_struct		*test_thread;
	int 			buf_id_offset;
	int				buf_id_tx;	/* byte */
	int				buf_id_rx;	/* byte */
	bool			buf_force_tx;	
	bool			buf_force_rx;	
	int				wsm_rx_seq;	/* byte */
	int				wsm_tx_seq;	/* byte */
	int				wsm_txframe_num;	/* byte */
	int				wsm_txconfirm_num;	/* byte */
	int				wsm_hifconfirm_num;	/* byte */
	int				wsm_hiftx_num;	/* byte */
	int				hw_bufs_used;
	int             hw_bufs_free;
	int				hw_bufs_free_init;
	u32 			n_xmits;
	u32				hw_xmits;
	char *			xmit_buff;
	int             xmit_buff_put;
	
	int 			hw_noconfirm_tx;
	struct sk_buff			*skb_cache;
	bool			device_can_sleep;
	bool            bh_running;
	/* Keep apollo awake (WUP = 1) 1 second after each scan to avoid
	 * FW issue with sleeping/waking up. */

	/* WSM */
	struct wsm_caps			wsm_caps;
	struct mutex			wsm_cmd_mux;
	struct wsm_buf			wsm_cmd_buf;
	struct wsm_cmd			wsm_cmd;
	struct wsm_tcp_filter_req  tcp_filter_req;	
	struct wsm_powersave_mode_req  ps_mode_req;	
	struct wsm_customer_cert_save_req cert_save_req;
	struct wsm_direct_trans_buffer_req direct_buffer_req;
	wait_queue_head_t		wsm_cmd_wq;
	atomic_t			tx_lock;
	u32				pending_frame_id;

#ifdef CONFIG_ATBM_SDIO_ATCMD
	u8 *at_cmd_buf[ATBM_AT_CMD_MAX_SW_CACHE];
	u32 at_cmd_put;
	u32 at_cmd_get;
#endif

	/* WSM events */
	spinlock_t		event_queue_lock;
	struct list_head	event_queue;
	struct work_struct	event_handler;

	int				tx_burst_idx;

	#ifndef OPER_CLOCK_USE_SEM
	struct mutex			wsm_oper_lock;
	#else
	struct semaphore		wsm_oper_lock;
	//struct timer_list		wsm_pm_timer;
	spinlock_t				wsm_pm_spin_lock;
	atomic_t				wsm_pm_running;
	#endif
	bool				powersave_enabled;
	int					extra_tx_headroom;
	/*
	*sta
	*/
	struct mutex sta_mtx;
	spinlock_t sta_lock;
	unsigned long num_sta;
	struct list_head sta_list, sta_pending_list;
	struct sta_info __rcu *sta_hash[STA_HASH_SIZE];
	struct sk_buff_head rx_skb_queue;
	bool   running_rx_handler;
	spinlock_t rx_path_lock;
	int tx_num_queued;
	bool tx_queue_overfull;
	spinlock_t tx_queue_lock;
};
#define ATBM_MAX_SSID_LEN		32

#define WEP_IV_LEN		4
#define WEP_ICV_LEN		4
#define ALG_CCMP_KEY_LEN	16
#define CCMP_HDR_LEN		8
#define CCMP_MIC_LEN		8
#define CCMP_TK_LEN		16
#define CCMP_PN_LEN		6
#define TKIP_IV_LEN		8
#define TKIP_ICV_LEN		4
#define CMAC_PN_LEN		6
#define WAPI_IV_LEN		18
#define WAPI_ICV_LEN		16

enum atbm_enc_type{
	ATBM_ENC_TYPE,
	ATBM_ENC_TKIP,
	ATBM_ENC_AES,
	ATNM_ENC_WAPI,
};
struct atbm_key_info{
	enum atbm_enc_type enc_type;
	u32  icv_len;
	u32  iv_len;
};
struct atbm_ap_config{
	u8 	  bssid[ETH_ALEN];
	u8    ssid[ATBM_MAX_SSID_LEN];
	u8    ssid_len;
	u8    password[64];
	u8    password_len;
	u8    channel;
	bool  wmm;
	bool  enc;
	bool  n_supports;
	u32   supp_rates;
	u32   mcs_mask;
	struct ieee80211_key group_key;
	struct ieee80211_key key;
};
/* Virtual Interface State. One copy per VIF */
struct atbm_vif {
#ifndef CONFIG_ATBM_SDIO_ATCMD
	struct net_device *ndev;
#endif
	atomic_t			enabled;
	spinlock_t			vif_lock;
	int					if_id;
	enum nl80211_iftype type;
	u8 					addr[ETH_ALEN];
	struct sk_buff_head skb_queue;
	struct work_struct work;
	struct wsm_set_pm		powersave_mode;
	struct atbm_ap_config	ap_info;
	struct atbm_common	*hw_priv;	
	u8					 connect_success;
	struct ieee80211_key group_key;
	u8 ptk_pn[8][CCMP_PN_LEN];
	u8 ptk_pn_init[8];
	u8 gtk_pn[CCMP_PN_LEN];
	u8 gtk_pn_init;
	u8 ptk_noqos_pn[CCMP_PN_LEN];
	u8 ptk_noqos_pn_init;
	u8 reserved[3];
};
static inline struct atbm_common *ABwifi_vifpriv_to_hwpriv(struct atbm_vif *priv)
{
	return priv->hw_priv;
}
static inline struct atbm_vif *ABwifi_hwpriv_to_vifpriv(struct atbm_common *hw_priv,
						int if_id)
{
	struct atbm_vif *priv;
	
	rcu_read_lock();
	if (((-1 == if_id) || (if_id >= ATBM_WIFI_MAX_VIFS))){
		atbm_printk_err("if_id = %d\n", if_id);
		rcu_read_unlock();
		return NULL;
	}

	priv = rcu_dereference(hw_priv->vif_list[if_id]);
	if(!priv)
		rcu_read_unlock();
	return priv;
}
static inline struct atbm_vif *__ABwifi_hwpriv_to_vifpriv(struct atbm_common *hw_priv,
						int if_id)
{
	
	if (((-1 == if_id) || (if_id >= ATBM_WIFI_MAX_VIFS))){
		atbm_printk_err("if_id = %d\n", if_id);
		return NULL;
	}

	return (hw_priv->vif_list[if_id]);
}

static inline int ABwifi_get_nr_hw_ifaces(struct atbm_common *hw_priv)
{
	return 1;
}

/* interfaces for the drivers */
int atbm_core_probe(const struct sbus_ops *sbus_ops,
		      struct sbus_priv *sbus,
		      struct device *pdev,
		      struct atbm_common **pself);
void atbm_core_release(struct atbm_common *self);
void atbm_xmit_linearize(struct atbm_common	*hw_priv,
	 struct wsm_tx *wsm,char *xmit,int xmit_len,struct sk_buff *skb);
int atbm_rx_bh_flush(struct atbm_common *hw_priv);
int atbm_tx_bh_flush(struct atbm_common *hw_priv);



#define ATBM_VOLATILE_SET(s,v)	*((volatile typeof(*(s)) *)(s)) = (v);smp_mb()
#define ATBM_VOLATILE_GET(s)	(*((volatile typeof(*(s)) *)(s)))

#define atbm_hw_priv_assign_pointer(p)	ATBM_VOLATILE_SET(&g_hw_priv,p)
#define atbm_hw_priv_dereference()		ATBM_VOLATILE_GET(&g_hw_priv)
#ifdef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
void atbm_oob_intr_set(struct sbus_priv *self, bool enable);
#endif

#define CAPABILITIES_ATBM_PRIVATE_IE 		BIT(1)
#define CAPABILITIES_NVR_IPC 				BIT(2)
#define CAPABILITIES_NO_CONFIRM 			BIT(3)
#define CAPABILITIES_SDIO_PATCH 			BIT(4)
#define CAPABILITIES_NO_BACKOFF 			BIT(5)
#define CAPABILITIES_CFO 					BIT(6)
#define CAPABILITIES_AGC 					BIT(7)
#define CAPABILITIES_TXCAL 					BIT(8)
#define CAPABILITIES_MONITOR 				BIT(9)
#define CAPABILITIES_CUSTOM 				BIT(10)
#define CAPABILITIES_SMARTCONFIG			BIT(11)
#define CAPABILITIES_ETF					BIT(12)
#define CAPABILITIES_LMAC_RATECTL			BIT(13)
#define CAPABILITIES_LMAC_TPC				BIT(14)
#define CAPABILITIES_LMAC_TEMPC				BIT(15)
#define CAPABILITIES_CTS_BUG				BIT(16)
#define CAPABILITIES_USB_RECOVERY_BUG		BIT(17)
#define CAPABILITIES_VIFADDR_LOCAL_BIT		BIT(18)
#define CAPABILITIES_USE_IPC 				BIT(19)
#define CAPABILITIES_OUTER_PA 				BIT(20)
#define CAPABILITIES_POWER_CONSUMPTION 		BIT(21)
#define CAPABILITIES_RSSI_DECIDE_TXPOWER 	BIT(22)
#define CAPABILITIES_RTS_LONG_DURATION 		BIT(23)
#define CAPABILITIES_TX_CFO_PPM_CORRECTION 	BIT(24)
#define CAPABILITIES_NOISE_SET_DCXO 		BIT(25)
#define CAPABILITIES_HW_CHECKSUM  			BIT(26)
#define CAPABILITIES_SINGLE_CHANNEL_MULTI_RX BIT(27)
#define CAPABILITIES_CFO_DCXO_CORRECTION BIT(28)
#define CAPABILITIES_EFUSE8 BIT(29)
#define CAPABILITIES_EFUSEI BIT(30)
#define CAPABILITIES_EFUSEB BIT(31)
#include "ieee80211_atbm_mem.h"
#include "ieee80211_atbm_skb.h"

#endif /* ATBM_APOLLO_H */
