/*
 * mac80211 glue code for mac80211 altobeam APOLLO drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on apollo code
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * Based on:
 * Copyright (c) 2006, Michael Wu <flamingice@sourmilk.net>
 * Copyright (c) 2007-2009, Christian Lamparter <chunkeey@web.de>
 * Copyright 2008, Johannes Berg <johannes@sipsolutions.net>
 *
 * Based on:
 * - the islsm (softmac prism54) driver, which is:
 *   Copyright 2004-2006 Jean-Baptiste Note <jbnote@gmail.com>, et al.
 * - stlc45xx driver
 *   Copyright (C) 2008 Nokia Corporation and/or its subsidiary(-ies).
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */
#ifdef LINUX_OS
/*Linux version 3.4.0 compilation*/
//#if (LINUX_VERSION_CODE >= KERNEL_VERSION(3,4,0))
#include<linux/module.h>
//#endif
#include <linux/init.h>
#include <linux/firmware.h>
#include <linux/etherdevice.h>
#include <linux/vmalloc.h>
#include <linux/random.h>
#include <linux/sched.h>
#include <net/atbm_mac80211.h>
#include <linux/debugfs.h>
#include <linux/slab.h>
#include <linux/kernel.h>
#include <linux/if_arp.h>
#include <linux/netdevice.h>
#include <linux/rtnetlink.h>

#ifdef CONFIG_ATBM_5G_PRETEND_2G
#include <net/regulatory.h>
#endif
#endif

#include "apollo.h"
#include "sbus.h"
#include "fwio.h"
#include "hwio.h"
#include "bh.h"
#include "debug.h"
#include "pm.h"
#include "svn_version.h"
#include "iface.h"
#include "wsm.h"
#include "atbm_ioctl.h"


MODULE_AUTHOR("wifi_software <wifi_software@altobeam.com>");
MODULE_DESCRIPTION("Softmac altobeam apollo wifi common code");
MODULE_LICENSE("GPL");
MODULE_ALIAS("atbm_core");

//1: HIF-Disconect  0: Normal
static int hif_sta = 0;
module_param(hif_sta, int, 0644);


extern int wifi_run_sta;
module_param(wifi_run_sta, int, 0644);
static int efuse = 0;
module_param(efuse, int, 0644);
static int driver_ver =DRIVER_VER;
module_param(driver_ver, int, 0644);
static int fw_ver = 0;
module_param(fw_ver, int, 0644);

#define verson_str(_ver) #_ver
#define verson(ver) verson_str(ver)
const char* hmac_ver = "HMAC_VER:"verson(DRIVER_VER);
#ifdef CUSTOM_FEATURE_MAC /* To use macaddr and PS Mode of customers */
#define PATH_WIFI_MACADDR	"/data/.mac.info"
#define PATH_WIFI_PSM_INFO		"/data/.psm.info"
#define PATH_WIFI_EFUSE	    "/data/.efuse.info"
int access_file(char *path, char *buffer, int size, int isRead);
#ifdef CUSTOM_FEATURE_PSM/* To control ps mode */
static int savedpsm = 0;
#endif
#endif

/*
*
*atbm log level control fs
*
*/
u32 atbm_printk_mask = ATBM_PRINTK_DEFAULT_MASK;

module_param(atbm_printk_mask, int, 0644);

static void atbm_configure_wifi_mode(struct atbm_common *hw_priv);

void atbm_set_fw_ver(struct atbm_common *hw_priv)
{
	fw_ver = hw_priv->wsm_caps.firmwareVersion;
}

static inline void __atbm_free_event_queue(struct list_head *list)
{
	while (!list_empty(list)) {
		struct atbm_wsm_event *event =
			list_first_entry(list, struct atbm_wsm_event,
			link);
		list_del(&event->link);
		atbm_kfree(event);
	}
}
void atbm_free_event_queue(struct atbm_common *hw_priv)
{
	LIST_HEAD(list);

	spin_lock_bh(&hw_priv->event_queue_lock);
	list_splice_init(&hw_priv->event_queue, &list);
	spin_unlock_bh(&hw_priv->event_queue_lock);

	__atbm_free_event_queue(&list);
}

int sdio_wakeup_reason = 0;

struct sdio_customer_cmd_req
{
	int cmd_id;
	char data[96];
};

void atbm_event_handler(struct work_struct *work)
{
	struct atbm_common *hw_priv = container_of(work, struct atbm_common, event_handler);
	struct atbm_vif *priv = NULL;
	struct atbm_wsm_event *event;
	LIST_HEAD(list);

	spin_lock_bh(&hw_priv->event_queue_lock);
	list_splice_init(&hw_priv->event_queue, &list);
	spin_unlock_bh(&hw_priv->event_queue_lock);
	if(atbm_bh_is_term(hw_priv))
	{
		goto event_handler_out;
	}
	mutex_lock(&hw_priv->conf_mutex);
	list_for_each_entry(event, &list, link) {
		if ((event->evt.eventId != WSM_EVENT_HOST_RMMOD)
			&& (event->evt.eventId != WSM_EVENT_HOST_INSMOD)
			&& (event->evt.eventId != WSM_EVENT_HOST_WAKEUP_REASON)
			&& (event->evt.eventId != WSM_EVENT_HOST_DISCONN_REASON)
			&& (event->evt.eventId != WSM_EVENT_HOST_CONN_ERR_REASON)
			&& (event->evt.eventId != WSM_EVENT_ATCMD_RECIVE)){
			priv = __ABwifi_hwpriv_to_vifpriv(hw_priv, event->if_id);
			if (!priv) {
				printk( "[CQM] Event for non existing interface, ignoring.\n");
				continue;
			}
		}
		switch (event->evt.eventId) {
			case WSM_EVENT_ERROR:
				/* I even don't know what is it about.. */
				//STUB();
				break;
			case WSM_EVENT_BSS_LOST:
			{
				struct HostDisConnectEvent * hostevent = (struct HostDisConnectEvent *)event->evt.buffer;
				atbm_ioctl_connect_async(NULL, 0);
#ifndef CONFIG_ATBM_SDIO_ATCMD
				if (priv->type == NL80211_IFTYPE_STATION){
					atbm_sta_disconnect_event(priv,hostevent->bssid);
				}
#endif
				break;
			}
			case WSM_EVENT_BSS_CONNECT:
			{
				struct HostConnectEvent * hostevent = (struct HostConnectEvent *)event->evt.buffer;

				printk( "hostevent->bssid %pM ipaddr %x\n",hostevent->bssid,hostevent->ipaddr);
				atbm_ioctl_connect_async(hostevent, 1);
#ifndef CONFIG_ATBM_SDIO_ATCMD
				if ((priv->type == NL80211_IFTYPE_STATION) && !(hostevent->connect_flag&BIT(1))){//6441 BIT1 notify ap mode
					atbm_sta_connect_event(priv,hostevent);
				}
				else {
					atbm_configure_wifi_mode(priv->hw_priv);
				#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
				{
					struct atbm_vif * vif=__ABwifi_hwpriv_to_vifpriv(hw_priv,0);
					if (vif != NULL)
					{
						atbm_set_ak_ip_info(vif->ndev, &hostevent->ipaddr, &hostevent->ipmask, &hostevent->gwaddr);
					}
				}
				#endif
				}
#endif
				break;
			}
			case WSM_EVENT_STA_ADD:
			{
#ifndef CONFIG_ATBM_SDIO_ATCMD
				atbm_sta_add_event(priv,*((int *)(event->evt.buffer)));
#endif
				break;
			}
			case WSM_EVENT_STA_LOSS:
			{
#ifndef CONFIG_ATBM_SDIO_ATCMD
				atbm_sta_loss_event(priv);
#endif
				break;
			}
			case WSM_EVENT_SMT_SUCCESS:
			{
				printk("SMARTCONFIG SUCCESS.\n");
				break;
			}
			case WSM_EVENT_SMT_FAIL:
			{
				printk("SMARTCONFIG FAIL.\n");
				break;
			}
			case WSM_EVENT_ETF_RX_MSG:
			{
				printk("%s", event->evt.buffer);
				break;
			}
			case WSM_EVENT_FW_UART_MSG:
			{
				printk("%s", event->evt.buffer);
				break;
			}
			case WSM_EVENT_HOST_RMMOD:
			{
				atbm_ioctl_driver_async(0);
				break;
			}
			case WSM_EVENT_HOST_INSMOD:
			{
				atbm_ioctl_driver_async(1);
				break;
			}
			case WSM_EVENT_HOST_WAKEUP_REASON:
			{
				u8 reason = *((u8 *)event->evt.buffer);
				atbm_ioctl_wakeup_async(reason);
				sdio_wakeup_reason = reason;
				break;
			}
			case WSM_EVENT_HOST_DISCONN_REASON:
			{
				u8 reason = *((u8 *)event->evt.buffer);
				atbm_ioctl_disconn_async(reason);
				break;
			}
			case WSM_EVENT_HOST_CONN_ERR_REASON:
			{
				u8 reason = *((u8 *)event->evt.buffer);
				atbm_ioctl_conn_err_async(reason);
				break;
			}
			case WSM_EVENT_HOST_CUSTOMER_CMD_REQ:
			{
				struct sdio_customer_cmd_req *req = (struct sdio_customer_cmd_req *)(event->evt.buffer);
				printk("cmdid:%d  data:%s\n", req->cmd_id, req->data);
				break;
			}
			case WSM_EVENT_HOST_CUSTOMER_PRIVATE:
			{
				atbm_ioctl_customer_private_event_async(event->evt.buffer);
				break;
			}
#ifdef CONFIG_ATBM_SDIO_ATCMD
			case WSM_EVENT_ATCMD_RECIVE:
			{
				atbm_ioctl_atcmd_event_async(event->evt.buffer);
				break;
			}
#endif
		}
	}
	mutex_unlock(&hw_priv->conf_mutex);
event_handler_out:
	__atbm_free_event_queue(&list);
}

#ifdef TIME_DEBUG
extern void jiffies_update(int is_first);
#endif

struct atbm_common *atbm_init_common(size_t hw_priv_data_len)
{
	struct atbm_common *hw_priv;

	hw_priv = kzalloc(hw_priv_data_len,0);
	if (hw_priv==NULL){
		printk("kzalloc(sizeof(atbm_common),0) error!!! \n");
		return 0;
	}
	hw_priv->extra_tx_headroom = WSM_TX_EXTRA_HEADROOM + 64 +
		8  /* TKIP IV */ +
		12 /* TKIP ICV and MIC */;
	hw_priv->workqueue = create_singlethread_workqueue("atbm_wq");	
	init_waitqueue_head(&hw_priv->wsm_cmd_wq);
	spin_lock_init(&hw_priv->event_queue_lock);
	INIT_LIST_HEAD(&hw_priv->event_queue);
	INIT_WORK(&hw_priv->event_handler, atbm_event_handler);
		
	mutex_init(&hw_priv->wsm_cmd_mux);
	mutex_init(&hw_priv->conf_mutex);
#ifndef OPER_CLOCK_USE_SEM
	mutex_init(&hw_priv->wsm_oper_lock);
#else
	sema_init(&hw_priv->wsm_oper_lock, 1);
	//init_timer(&hw_priv->wsm_pm_timer);
	//hw_priv->wsm_pm_timer.data = (unsigned long)hw_priv;
	//hw_priv->wsm_pm_timer.function = atbm_pm_timer;
	spin_lock_init(&hw_priv->wsm_pm_spin_lock);
	atomic_set(&hw_priv->wsm_pm_running, 0);
#endif
	wsm_buf_init(&hw_priv->wsm_cmd_buf);
	spin_lock_init(&hw_priv->wsm_cmd.lock);

#ifdef CONFIG_ATBM_SDIO_ATCMD
	atbm_sdio_atcmd_buf_init(hw_priv);
#endif
	
	atbm_skb_queue_head_init(&hw_priv->rx_frame_queue);
	atbm_skb_queue_head_init(&hw_priv->tx_frame_queue);
	atbm_skb_queue_head_init(&hw_priv->rx_skb_queue);
	
#ifndef CONFIG_ATBM_SDIO_ATCMD
	spin_lock_init(&hw_priv->rx_path_lock);
	sta_info_init(hw_priv);
	spin_lock_init(&hw_priv->tx_queue_lock);
#endif
	return hw_priv;
}

EXPORT_SYMBOL_GPL(atbm_init_common);

void atbm_free_common( struct atbm_common  *dev)
{
	if (dev->wsm_caps.firmwareVersion < 13549){
		u16 val16;
		int ret;
		#ifdef TIME_DEBUG
		jiffies_update(0);
		#endif
		//hare sdio + iot,let lmac know host initial done .add by wp
		/* Set wakeup bit in device */
		ret = atbm_reg_read_16(dev, ATBM_HIFREG_CONTROL_REG_ID, &val16);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: set_wakeup: can't read " \
				"control register.\n", __func__);
			goto out;
		}
		
		ret = atbm_reg_write_16(dev, ATBM_HIFREG_CONTROL_REG_ID, val16 & ~ATBM_HIFREG_CONT_WUP_BIT);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: set_wakeup: can't write " \
				"control register.\n", __func__);
			goto out;
		}
	}
out:
	kfree(dev);
}
EXPORT_SYMBOL_GPL(atbm_free_common);

void atbm_clear_wakeup_reg( struct atbm_common  *dev)
{
	u16 val16;
	int ret;

	//hare sdio + iot,let lmac know host initial done .add by wp
	/* Set wakeup bit in device */
	ret = atbm_reg_read_16_for_sleep(dev, ATBM_HIFREG_CONTROL_REG_ID, &val16);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: set_wakeup: can't read " \
			"control register.\n", __func__);
	}
	
	ret = atbm_reg_write_16_for_sleep(dev, ATBM_HIFREG_CONTROL_REG_ID, val16 & ~ATBM_HIFREG_CONT_WUP_BIT);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: set_wakeup: can't write " \
			"control register.\n", __func__);
	}
}

extern int is_pre_rmmod;
void atbm_unregister_common(struct atbm_common *hw_priv)
{
	atbm_printk_exit("atbm_unregister_common.++\n");
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	rtnl_lock();
	atbm_remove_interfaces(hw_priv);
	rtnl_unlock();
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	if ((hw_priv->wsm_caps.firmwareVersion < 13549) || (!is_pre_rmmod))
	{
#if (ATBM_WIFI_PLATFORM != PLATFORM_XM)		
		hw_priv->sbus_ops->irq_unsubscribe(hw_priv->sbus_priv);
#endif
	}
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	hw_priv->init_done = 0;
	if ((hw_priv->wsm_caps.firmwareVersion < 13549) || (!is_pre_rmmod))
	{
		hw_priv->close_driver = 1;
		if(hw_priv->sbus_ops->sbus_xmit_func_deinit)
			hw_priv->sbus_ops->sbus_xmit_func_deinit(hw_priv->sbus_priv);
		if(hw_priv->sbus_ops->sbus_rev_func_deinit)	
			hw_priv->sbus_ops->sbus_rev_func_deinit(hw_priv->sbus_priv);
	}
	atbm_unregister_bh(hw_priv);
	//atbm_debug_release_common(hw_priv);
	atbm_rx_bh_flush(hw_priv);
	atbm_tx_bh_flush(hw_priv);
	mutex_destroy(&hw_priv->conf_mutex);
	flush_workqueue(hw_priv->workqueue);
	destroy_workqueue(hw_priv->workqueue);
	hw_priv->workqueue = NULL;
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	wsm_buf_deinit(&hw_priv->wsm_cmd_buf);
	if (hw_priv->skb_cache) {
		atbm_dev_kfree_skb(hw_priv->skb_cache);
		hw_priv->skb_cache = NULL;
	}

#ifdef CONFIG_PM
	atbm_pm_deinit(&hw_priv->pm_state);
#endif

	atbm_printk_exit("atbm_unregister_common.--\n");
}



void atbm_monitor_pc(struct atbm_common *hw_priv);
int atbm_register_test_thread(struct atbm_common *hw_priv);
//#ifdef RESET_CHANGE
struct atbm_common *g_hw_priv=0;
int hw_net_cfg_ok=0;
//#endif
static void atbm_get_mac_address(struct atbm_common *hw_priv)
{
	struct	wsm_sdio_getconfig_cnf cnf;
	wsm_get_config(hw_priv,&cnf,sizeof(cnf));
	hw_priv->mac_addr[0] = cnf.macaddr[0];
	hw_priv->mac_addr[1] = cnf.macaddr[1];
	hw_priv->mac_addr[2] = cnf.macaddr[2];
	hw_priv->mac_addr[3] = cnf.macaddr[3];
	hw_priv->mac_addr[4] = cnf.macaddr[4];
	hw_priv->mac_addr[5] = cnf.macaddr[5];

	atbm_printk_init("atbm_get_mac_address.%x:%x:%x:%x:%x\n",hw_priv->mac_addr[1],hw_priv->mac_addr[2],hw_priv->mac_addr[3],hw_priv->mac_addr[4],hw_priv->mac_addr[5]);
}

static void atbm_configure_wifi_mode(struct atbm_common *hw_priv)
{
	struct atbm_vif * vif;
	struct  wsm_sdio_getconfig_cnf cnf;
	wsm_get_config(hw_priv,&cnf,sizeof(cnf));

	vif =__ABwifi_hwpriv_to_vifpriv(hw_priv,0);
	if (vif != NULL){
		if(cnf.WifiMode){
			vif->type = NL80211_IFTYPE_AP;
		}
		else {
			vif->type = NL80211_IFTYPE_STATION;
		}
		atbm_printk_init("wifi mode:%s\n",cnf.WifiMode?"AP":"STA");
		if (cnf.WifiMode){
			struct wsm_ap_cfg_get_req apcfg_get;

			if (wsm_get_ap_cfg(hw_priv,&apcfg_get,sizeof(apcfg_get)) == 0){
				if(apcfg_get.ap_cfg.key_mgmt == KEY_MGMT_NONE){
					vif->ap_info.group_key.key_type = IEEE80211_ENC_TYPE;
					vif->ap_info.key.key_type = IEEE80211_ENC_TYPE;
				}
				else if((apcfg_get.ap_cfg.key_mgmt == KEY_MGMT_WEP) || 
				(apcfg_get.ap_cfg.key_mgmt == KEY_MGMT_WEP_SHARED)){
					atbm_printk_err("%s:wep\n",__func__);
					vif->ap_info.group_key.key_type = IEEE80211_ENC_WEP;
					vif->ap_info.key.key_type = IEEE80211_ENC_WEP;
					vif->ap_info.group_key.conf.iv_len = WEP_IV_LEN;
					vif->ap_info.group_key.conf.icv_len = WEP_ICV_LEN;
					vif->ap_info.key.conf.iv_len = WEP_IV_LEN;
					vif->ap_info.key.conf.icv_len = WEP_ICV_LEN;
				}else if(apcfg_get.ap_cfg.key_mgmt == KEY_MGMT_WPA){
					atbm_printk_err("%s:tkip\n",__func__);
					vif->ap_info.group_key.key_type = IEEE80211_ENC_TKIP;
					vif->ap_info.key.key_type = IEEE80211_ENC_TKIP;
					vif->ap_info.group_key.conf.iv_len = TKIP_IV_LEN;
					vif->ap_info.group_key.conf.icv_len = TKIP_ICV_LEN;
					vif->ap_info.key.conf.iv_len = TKIP_IV_LEN;
					vif->ap_info.key.conf.icv_len = TKIP_ICV_LEN;
				}else if(apcfg_get.ap_cfg.key_mgmt == KEY_MGMT_WPA2){
					atbm_printk_err("%s:aes\n",__func__);
					vif->ap_info.group_key.key_type = IEEE80211_ENC_AES;
					vif->ap_info.key.key_type = IEEE80211_ENC_AES;
					vif->ap_info.group_key.conf.iv_len = CCMP_HDR_LEN;
					vif->ap_info.group_key.conf.icv_len = CCMP_MIC_LEN;
					vif->ap_info.key.conf.iv_len = CCMP_HDR_LEN;
					vif->ap_info.key.conf.icv_len = CCMP_MIC_LEN;
				}
				memcpy(&vif->group_key,&vif->ap_info.group_key,sizeof(struct ieee80211_key));
			}
		}
	}
}

#ifndef CONFIG_ATBM_SDIO_ATCMD
 void atbm_get_connectconfig(struct atbm_common *hw_priv)
{
	struct	wsm_sdio_getconfig_cnf cnf;	
	struct atbm_vif *vif = NULL;
	
	wsm_get_config(hw_priv,&cnf,sizeof(cnf));
	vif = __ABwifi_hwpriv_to_vifpriv(hw_priv,0);
	vif->connect_success = cnf.bconnect;
	if(vif->connect_success){
		atbm_sta_connect_event(vif,&cnf.con_event);
	}
	
	atbm_printk_init("atbm_get_mac_address.%x:%x:%x:%x:%x\n",hw_priv->mac_addr[1],hw_priv->mac_addr[2],hw_priv->mac_addr[3],hw_priv->mac_addr[4],hw_priv->mac_addr[5]);
}
#endif

 void dump_mem(u8 *data, int len);

 void atbm_set_tcp_port_filter(struct atbm_common *hw_priv)
{
	wsm_set_tcp_filter(hw_priv,&hw_priv->tcp_filter_req,sizeof(hw_priv->tcp_filter_req));
	
	atbm_printk_init("tcp_port_filter addcnt.%x:\n",hw_priv->tcp_filter_req.des_cnt);
	//dump_mem((u8 *)(&hw_priv->tcp_filter_req),sizeof(hw_priv->tcp_filter_req));
}

 void atbm_set_psmode(struct atbm_common *hw_priv)
{
	wsm_set_psmode(hw_priv,&hw_priv->ps_mode_req,sizeof(hw_priv->ps_mode_req));
}

int atbm_notify_sta_connect_ok(struct atbm_common *hw_priv)
{
	int ret = 0;
	struct wsm_generic_req notify_req;

	ret = wsm_host_network_ok_notify(hw_priv, &notify_req, sizeof(notify_req));
	if (ret)
	{
		atbm_printk_err("%s: wsm_host_network_ok_notify err. can not receive any datas!\n", __func__);
	}
	return ret;
}

extern int has_func_enable;

int atbm_core_probe(const struct sbus_ops *sbus_ops,
		      struct sbus_priv *sbus,
		      struct device *pdev,
		      struct atbm_common **pself)
{
	int err = -ENOMEM;
	struct atbm_common *hw_priv=NULL;
	u32 val32 = 0;
	int ret = 0;

	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	hw_priv = atbm_init_common(sizeof(struct atbm_common));
	if (!hw_priv)
		goto err;

	atbm_hw_priv_assign_pointer(hw_priv);
	hw_priv->init_done = 0;
	hw_priv->sbus_ops = sbus_ops;
	hw_priv->sbus_priv = sbus;
	hw_priv->pdev = pdev;
	hw_priv->tcp_filter_req.Flags= HI_SDIO_FILTER_F_ICMP|HI_SDIO_FILTER_F_ARP|HI_SDIO_FILTER_F_DNS;
	hw_priv->tcp_filter_req.status= 0;
	hw_priv->tcp_filter_req.des_cnt = 1;
	hw_priv->tcp_filter_req.src_cnt = 1;
	hw_priv->tcp_filter_req.des_tcpport[0] =  htons(5001);
	hw_priv->tcp_filter_req.src_tcpport[0] =  htons(5001);
	
	hw_priv->ps_mode_req.powerave_level = 1;
	hw_priv->ps_mode_req.powersave_mode = HAL_NO_SLEEP;
	
	hw_priv->buf_force_rx=1;
	hw_priv->buf_force_tx=1;

	*pself = hw_priv;
#ifdef CONFIG_PM
	err = atbm_pm_init(&hw_priv->pm_state, hw_priv);
	if (err) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR, "Cannot init PM. (%d).\n",
				err);
		goto err1;
	}
#endif

	if (has_func_enable) {
		/* set default blksz */
		hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
		hw_priv->sbus_ops->set_block_size(hw_priv->sbus_priv, 512);
		hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
		/* generate sw irq */
		atbm_direct_read_reg_32(hw_priv,0x16100008, &val32);
		val32 |=  0 << 27;
		atbm_direct_write_reg_32(hw_priv,0x16100008, val32);
		atbm_direct_read_reg_32(hw_priv,0x1610000c, &val32);
		val32 |=  1 << 0;
		atbm_direct_write_reg_32(hw_priv,0x1610000c, val32);
	}

	err = atbm_register_bh(hw_priv);
	if (err)
		goto err1;
	/*
	*init bus tx/rx
	*/
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	if(hw_priv->sbus_ops->sbus_xmit_func_init)
		err = hw_priv->sbus_ops->sbus_xmit_func_init(hw_priv->sbus_priv);
	if(hw_priv->sbus_ops->sbus_rev_func_init)
		err |= hw_priv->sbus_ops->sbus_rev_func_init(hw_priv->sbus_priv);

	if(err){
		atbm_printk_err("rev and xmit init err\n");
		goto err1;
	}
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
reload_fw:
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	WARN_ON(hw_priv->sbus_ops->set_block_size(hw_priv->sbus_priv,DOWNLOAD_BLOCK_SIZE));
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
#endif
	err = atbm_load_firmware(hw_priv);
	if (err){
		atbm_printk_err("atbm_load_firmware ERROR!\n");
		goto err2;
	}

	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	WARN_ON(hw_priv->sbus_ops->set_block_size(hw_priv->sbus_priv,SDIO_BLOCK_SIZE));
	atbm_printk_init("set_block_size=%d\n", SDIO_BLOCK_SIZE);
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);

	hw_priv->init_done = 1;

	ret = hw_priv->sbus_ops->irq_subscribe(hw_priv->sbus_priv,
			(sbus_irq_handler)atbm_irq_handler, hw_priv);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't register IRQ handler.\n", __func__);
		//goto out;
	}

	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif

#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
__wait_start_up:
#endif
//fix mstar CVT suspend bug,in CVT mstar suspend wait_event_interruptible_timeout sometime will not delay
	{
		int loop =0;
		atbm_printk_always("mdelay wait wsm_startup_done  !!\n");
		while(hw_priv->wsm_caps.firmwareReady !=1){
			mdelay(10);
			schedule_timeout_interruptible(msecs_to_jiffies(20));
			if(loop++>300){
				atbm_printk_init("wait_event_interruptible_timeout wsm_startup_done timeout ERROR !!\n");
				#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
				goto __wait_start_up;
				#endif
				atbm_monitor_pc(hw_priv);
				if(hw_priv->sbus_ops->sbus_reset_chip){
						atbm_printk_err("reload fw\n");
						if(hw_priv->sbus_ops->irq_unsubscribe)
							hw_priv->sbus_ops->irq_unsubscribe(hw_priv->sbus_priv);
						hw_priv->sbus_ops->sbus_reset_chip(hw_priv->sbus_priv);
						goto reload_fw;
				}else {
					err = -ETIMEDOUT;
					goto err3;
				}
			}
		}
	}
	if (err) {
		goto err3;
	}

	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	//mdelay(100);
	hw_priv->wsm_caps.firmwareReady = 1;
	atbm_get_mac_address(hw_priv);
#ifdef CONFIG_PM
	atbm_pm_stay_awake(&hw_priv->pm_state, 6 * HZ);
#endif  //#ifdef CONFIG_PM
	//atbm_set_psmode(hw_priv);
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	
#ifdef CONFIG_ATBM_SDIO_ATCMD
	atbm_netdev_none(hw_priv);
#else //CONFIG_ATBM_SDIO_ATCMD
	rtnl_lock();
	err = atbm_netdev_add(hw_priv,"wlan0");
	rtnl_unlock();
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
	atbm_config_ak_net_mac(hw_priv->vif_list[0]->ndev);
#endif
	//atbm_setup_mac(hw_priv);
#endif //CONFIG_ATBM_SDIO_ATCMD

	hw_net_cfg_ok = 1;
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	atbm_configure_wifi_mode(hw_priv);
	return err;

err3:
	//sbus_ops->reset(sbus);
	hw_priv->sbus_ops->irq_unsubscribe(hw_priv->sbus_priv);
err2:
	atbm_unregister_bh(hw_priv);
err1:
	/*
	*init bus tx/rx
	*/
	if(hw_priv->sbus_ops->sbus_xmit_func_deinit)
		hw_priv->sbus_ops->sbus_xmit_func_deinit(hw_priv->sbus_priv);
	if(hw_priv->sbus_ops->sbus_rev_func_deinit)
		hw_priv->sbus_ops->sbus_rev_func_deinit(hw_priv->sbus_priv);	
	wsm_buf_deinit(&hw_priv->wsm_cmd_buf);
#ifdef CONFIG_PM
	atbm_pm_deinit(&hw_priv->pm_state);
#endif
	atbm_free_common(hw_priv);
err:
	*pself=NULL;
	if(hw_priv)
		hw_priv->init_done = 0;
	return err;
}
EXPORT_SYMBOL_GPL(atbm_core_probe);

void atbm_core_release(struct atbm_common *self)
{
	atbm_unregister_common(self);
	atbm_free_common(self);
	hw_net_cfg_ok = 0;
	return;
}
EXPORT_SYMBOL_GPL(atbm_core_release);
#ifdef CUSTOM_FEATURE_MAC /* To use macaddr and ps mode of customers */
int access_file(char *path, char *buffer, int size, int isRead)
{
	int ret=0;
	struct file *fp;
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0))
	mm_segment_t old_fs = get_fs();
#endif
	if(isRead)
		fp = filp_open(path,O_RDONLY,S_IRUSR);
	else
		fp = filp_open(path,O_CREAT|O_WRONLY,S_IRUSR);

	if (IS_ERR(fp)) {
		atbm_printk_err("apollo wifi : can't open %s\n",path);
		return -1;
	}

	if(isRead)
	{
		if(fp->f_op->read == NULL) {
			atbm_printk_err("apollo wifi : Not allow to read\n");
			return -2;
		}
		else {
			fp->f_pos = 0;
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0))
			set_fs(KERNEL_DS);
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0))
			ret = kernel_read(fp,buffer,size,&fp->f_pos);
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 9, 37))
			ret = kernel_read(fp,fp->f_pos,buffer,size);
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 9, 14))
			ret = kernel_read(fp,&fp->f_pos,buffer,size);
#else
			ret = vfs_read(fp,buffer,size,&fp->f_pos);
#endif
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0))
			set_fs(old_fs);
#endif
		}
	}
	else
	{
		if(fp->f_op->write == NULL) {
			atbm_printk_err("apollo wifi : Not allow to write\n");
			return -2;
		}
		else {
			fp->f_pos = 0;
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0))
			set_fs(KERNEL_DS);
#endif
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0))
			ret = kernel_write(fp,buffer,size,&fp->f_pos);
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 9, 37))
			ret = kernel_write(fp,buffer,size,fp->f_pos);
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4, 9, 14))
			ret = kernel_write(fp,&fp->f_pos,buffer,size);
#else
			ret = vfs_write(fp,buffer,size,&fp->f_pos);
#endif
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0))
			set_fs(old_fs);
#endif
		}
	}
	filp_close(fp,NULL);

	atbm_printk_debug("apollo wifi : access_file return code(%d)\n",ret);
	return ret;
}
#endif
