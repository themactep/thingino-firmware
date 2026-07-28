/*
 * WSM host interface (HI) implementation for altobeam APOLLO mac80211 drivers.
 *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 *  Based on 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifdef LINUX_OS
#include <linux/skbuff.h>
#include <linux/wait.h>
#include <linux/skbuff.h>
#include <linux/delay.h>
#include <linux/sched.h>
#include <linux/random.h>
#endif

#include "apollo.h"
#include "wsm.h"
#include "bh.h"
#include "debug.h"
#include "hwio.h"
#include "sbus.h"
#include "atbm_ioctl_ext.h"

void atbm_rx_cb(struct atbm_vif *priv,
		  struct wsm_rx *arg,
		  struct sk_buff **skb_p);

extern int test_cnt_packet;

#define WSM_CMD_TIMEOUT		(60 * HZ) /* With respect to interrupt loss */
#define WSM_CMD_SCAN_TIMEOUT	(15 * HZ) /* With respect to interrupt loss */
#define WSM_CMD_JOIN_TIMEOUT	(18 * HZ) /* Join timeout is 5 sec. in FW   */
#define WSM_CMD_START_TIMEOUT	(17 * HZ)
#define WSM_CMD_RESET_TIMEOUT	(14 * HZ) /* 2 sec. timeout was observed.   */
#define WSM_CMD_DEFAULT_TIMEOUT	(40 * HZ)
#define WSM_SKIP(buf, size)						\
	do {								\
		if (unlikely((buf)->data + size > (buf)->end))		\
			goto underflow;					\
		(buf)->data += size;					\
	} while (0)

#define WSM_GET(buf, ptr, size)						\
	do {								\
		if (unlikely((buf)->data + size > (buf)->end))		\
			goto underflow;					\
		memcpy(ptr, (buf)->data, size);				\
		(buf)->data += size;					\
	} while (0)

#define __WSM_GET(buf, type, cvt)					\
	({								\
		type val;						\
		if (unlikely((buf)->data + sizeof(type) > (buf)->end))	\
			goto underflow;					\
		val = cvt(*(type *)(buf)->data);			\
		(buf)->data += sizeof(type);				\
		val;							\
	})

#define WSM_GET8(buf)  __WSM_GET(buf, u8, (u8))
#define WSM_GET16(buf) __WSM_GET(buf, u16, __le16_to_cpu)
#define WSM_GET32(buf) __WSM_GET(buf, u32, __le32_to_cpu)

#define WSM_PUT(buf, ptr, size)						\
	do {								\
		if(buf == NULL)					\
			goto nomem;					\
		if (unlikely((buf)->data + size > (buf)->end))		\
			if (unlikely(wsm_buf_reserve((buf), size)))	\
				goto nomem;				\
		memcpy((buf)->data, ptr, size);				\
		(buf)->data += size;					\
	} while (0)

#define __WSM_PUT(buf, val, type, cvt)					\
	do {								\
		if(buf == NULL)					\
			goto nomem;					\
		if (unlikely((buf)->data + sizeof(type) > (buf)->end))	\
			if (unlikely(wsm_buf_reserve((buf), sizeof(type)))) \
				goto nomem;				\
		*(type *)(buf)->data = cvt(val);			\
		(buf)->data += sizeof(type);				\
	} while (0)
	
#define WSM_PUT8(buf, val)  __WSM_PUT(buf, val, u8, (u8))
#define WSM_PUT16(buf, val) __WSM_PUT(buf, val, u16, __cpu_to_le16)
#define WSM_PUT32(buf, val) __WSM_PUT(buf, val, u32, __cpu_to_le32)
struct wsm_shmem_arg_s {
	void *buf;
	size_t buf_size;
};

struct wsm_generic_get_arg_s {
	void *buf;
	size_t buf_size;
};


static void wsm_buf_reset(struct wsm_buf *buf);
static int wsm_buf_reserve(struct wsm_buf *buf, size_t extra_size);
int wsm_write_shmem_confirm(struct atbm_common *hw_priv,
				struct wsm_shmem_arg_s *arg,
				struct wsm_buf *buf);
int wsm_read_shmem_confirm(struct atbm_common *hw_priv,
				struct wsm_shmem_arg_s *arg,
				struct wsm_buf *buf);

int wsm_generic_get_confirm(struct atbm_common *hw_priv,
				struct wsm_generic_get_arg_s *arg, struct wsm_buf *buf);

static int wsm_cmd_send(struct atbm_common *hw_priv,
			struct wsm_buf *buf,
			void *arg, u16 cmd, long tmo, int if_id);


/**********************/
//1: Exception  0: Normal
int wifi_run_sta = 0;
void atbm_wifi_run_status_set(int status)
{
	wifi_run_sta = status;
	return;
}
int atbm_wifi_run_status_get(void)
{
	return wifi_run_sta;
}
/***********************/

void wsm_cmd_lock(struct atbm_common *hw_priv)
{
	mutex_lock(&hw_priv->wsm_cmd_mux);
}

void wsm_cmd_unlock(struct atbm_common *hw_priv)
{
	mutex_unlock(&hw_priv->wsm_cmd_mux);
}
static int wsm_oper_lock_flag=0;
static inline void wsm_oper_lock(struct atbm_common *hw_priv)
{
	#ifndef OPER_CLOCK_USE_SEM
	mutex_lock(&hw_priv->wsm_oper_lock);
	#else
	down(&hw_priv->wsm_oper_lock);
	#endif
	wsm_oper_lock_flag=1; 
}

void wsm_oper_unlock(struct atbm_common *hw_priv)
{
	wsm_oper_lock_flag=0;
	#ifndef OPER_CLOCK_USE_SEM
	mutex_unlock(&hw_priv->wsm_oper_lock);
	#else
	up(&hw_priv->wsm_oper_lock);
	#endif
}
/* ******************************************************************** */
/* WSM API implementation						*/

/* ******************************************************************** */

int wsm_reset(struct atbm_common *hw_priv, const struct wsm_reset *arg,
		int if_id)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	u16 cmd = 0x000A | WSM_TX_LINK_ID(arg->link_id);

	wsm_cmd_lock(hw_priv);

	WSM_PUT32(buf, arg->reset_statistics ? 0 : 1);
	ret = wsm_cmd_send(hw_priv, buf, NULL, cmd, WSM_CMD_RESET_TIMEOUT,
				if_id);
	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

/* ******************************************************************** */

struct wsm_mib {
	u16 mibId;
	void *buf;
	size_t buf_size;
};
static int wsm_event_indication(struct atbm_common *hw_priv,
				struct wsm_buf *buf,
				int interface_link_id)
{
	int first;
	struct atbm_wsm_event *event = NULL;
	struct atbm_vif *priv;
	u32 eventid=0;

	eventid=__le32_to_cpu(WSM_GET32(buf));
	if ((eventid != WSM_EVENT_HOST_RMMOD)
		&& (eventid != WSM_EVENT_HOST_INSMOD)
		&& (eventid != WSM_EVENT_HOST_WAKEUP_REASON)
		&& (eventid != WSM_EVENT_HOST_DISCONN_REASON)
		&& (eventid != WSM_EVENT_HOST_CONN_ERR_REASON)
		&& (eventid != WSM_EVENT_SDIO_INPUTCHAN_EVNET)){
		priv = ABwifi_hwpriv_to_vifpriv(hw_priv, interface_link_id);

		if (unlikely(!priv)) {
			atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "[WSM] Event: %d for removed "
				   "interface, ignoring\n", eventid);
			return 0;
		}

		if (unlikely(priv->type == NL80211_IFTYPE_UNSPECIFIED)) {
			rcu_read_unlock();
			/* STA is stopped. */
			return 0;
		}
		rcu_read_unlock();
	}

	if(eventid == WSM_EVENT_SDIO_INPUTCHAN_EVNET){
		hw_priv->hw_xmits =__le32_to_cpu(WSM_GET32(buf));	
		atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "%s update hw_xmits:%d...\n", __func__, hw_priv->hw_xmits);
		atbm_bh_wakeup(hw_priv);
	}
	else {
		event = atbm_kzalloc(sizeof(struct atbm_wsm_event), GFP_KERNEL);

		
		if(event == NULL){
			WARN_ON(1);
			return 0;
		}

		u32 event_size = SDIO_EVENT_IND_LEN;
		if (hw_priv->wsm_caps.firmwareVersion < 12802)
		{
			event_size = 128;
		}
		event->evt.eventId = eventid;	
		WSM_GET(buf, event->evt.buffer, event_size);
		event->if_id = interface_link_id;

		atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "[WSM] Event: %d\n",event->evt.eventId);
		//frame_hexdump("eventbuf:",event->evt.buffer,64);
		spin_lock_bh(&hw_priv->event_queue_lock);
		first = list_empty(&hw_priv->event_queue);
		list_add_tail(&event->link, &hw_priv->event_queue);
		spin_unlock_bh(&hw_priv->event_queue_lock);

		if (first)
			atbm_hw_priv_queue_work(hw_priv, &hw_priv->event_handler);
	}

	return 0;

underflow:
	if(event)
		atbm_kfree(event);
	return -EINVAL;
}

/* ******************************************************************** */
/* WSM TX								*/
static void wsm_cmd_hif_ximt(struct atbm_common *hw_priv)
{
	if(!hw_priv->sbus_ops->sbus_wsm_write){
		atbm_bh_wakeup(hw_priv);
	}else {
		hw_priv->sbus_ops->sbus_wsm_write(hw_priv->sbus_priv);
	}
}

int wsm_cmd_send(struct atbm_common *hw_priv,
		 struct wsm_buf *buf,
		 void *arg, u16 cmd, long tmo, int if_id)
{
	size_t buf_len = buf->data - buf->begin;
	struct wsm_hdr_tx * wsm_h = (struct wsm_hdr_tx *)buf->begin;
	int ret;
	
	if(atbm_bh_is_term(hw_priv)){
		wsm_buf_reset(buf);
		return -3;
	}

	if(cmd > WSM_EXTEND_MSG_REQ_ID){
		wsm_buf_reset(buf);
		return -1;
	}
	
	if (cmd == 0x0006) /* Write MIB */{
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "[WSM] >>> 0x%.4X [MIB: 0x%.4X] (%d)\n",
			cmd, __le16_to_cpu(((__le16 *)buf->begin)[sizeof(struct wsm_hdr_tx)/2]),
			buf_len);
	}
	else {
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "[WSM] >>> 0x%.4X (%d)\n", cmd, buf_len);
	}

	/* Fill HI message header */
	/* BH will add sequence number */

	/* TODO:COMBO: Add if_id from  to the WSM header */
	/* if_id == -1 indicates that command is HW specific,
	 * eg. wsm_configuration which is called during driver initialzation
	 *  (mac80211 .start callback called when first ifce is created. )*/

	/* send hw specific commands on if 0 */
	if (if_id == -1)
		if_id = 0;
	wsm_h = (struct wsm_hdr_tx *)buf->begin;

	wsm_h->len =__cpu_to_le16(buf_len);
	wsm_h->id =  __cpu_to_le16(cmd |(if_id << 6) );

	spin_lock_bh(&hw_priv->wsm_cmd.lock);
    BUG_ON(hw_priv->wsm_cmd.ptr);
	hw_priv->wsm_cmd.done = 0;
	hw_priv->wsm_cmd.ptr = buf->begin;
	hw_priv->wsm_cmd.len = buf_len;
	hw_priv->wsm_cmd.arg = arg;
	hw_priv->wsm_cmd.cmd = cmd;
	spin_unlock_bh(&hw_priv->wsm_cmd.lock);
	hw_priv->sbus_ops->power_mgmt(hw_priv->sbus_priv, false);

	wsm_cmd_hif_ximt(hw_priv);
	if (atbm_bh_is_term(hw_priv)) {
		/* Do not wait for timeout if BH is dead. Exit immediately. */
		ret = 0;
	} else {
		long wsm_cmd_starttime = jiffies;
		long wsm_cmd_runtime;
		long wsm_cmd_max_tmo = WSM_CMD_DEFAULT_TIMEOUT;

		/* Give start cmd a little more time */
		if (tmo == WSM_CMD_START_TIMEOUT)
			wsm_cmd_max_tmo = WSM_CMD_START_TIMEOUT;

		if (tmo == WSM_CMD_SCAN_TIMEOUT)
			wsm_cmd_max_tmo = WSM_CMD_SCAN_TIMEOUT;
		
		tmo = wsm_cmd_max_tmo/4+1;
		
		/* Firmware prioritizes data traffic over control confirm.
		 * Loop below checks if data was RXed and increases timeout
		 * accordingly. */
		do {
			/* It's safe to use unprotected access to
			 * wsm_cmd.done here */
			ret = atbm_wait_event_timeout_stay_awake(hw_priv,
					hw_priv->wsm_cmd_wq,
					hw_priv->wsm_cmd.done
					, tmo,true);
			wsm_cmd_runtime = jiffies - wsm_cmd_starttime;
			if(!ret  &&
					wsm_cmd_runtime < wsm_cmd_max_tmo){
				//wakeup again
				wsm_cmd_hif_ximt(hw_priv);
			}
		} while (!ret  &&
					wsm_cmd_runtime < wsm_cmd_max_tmo);
	}

	if (unlikely(ret == 0)) {
		u16 raceCheck;
		atbm_printk_err("wsm_cmd_send cmd(%x) not send to fw wsm_recovery last_send_cmd %x\n",hw_priv->wsm_cmd.cmd,hw_priv->wsm_cmd.last_send_cmd);

		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		raceCheck = hw_priv->wsm_cmd.cmd;
		if(hw_priv->wsm_cmd.ptr){
			atbm_printk_err("wsm_cmd_send cmd not send to fw\n");
		}
		atbm_printk_err("wsm_cmd_send,buffused(%d)\n",hw_priv->hw_bufs_used);
		hw_priv->wsm_cmd.arg = NULL;
		hw_priv->wsm_cmd.ptr = NULL;
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);
		

		/* Race condition check to make sure _confirm is not called
		 * after exit of _send */
		if (raceCheck == 0xFFFF) {
			/* If wsm_handle_rx got stuck in _confirm we will hang
			 * system there. It's better than silently currupt
			 * stack or heap, isn't it? */
			BUG_ON(atbm_wait_event_timeout_stay_awake(hw_priv,
					hw_priv->wsm_cmd_wq,
					hw_priv->wsm_cmd.done
		,WSM_CMD_LAST_CHANCE_TIMEOUT,true) <= 0);
		}
		atbm_printk_err("wsm_cmd_send timeout cmd %x tmo %ld\n",cmd,tmo);
		
		/* Kill BH thread to report the error to the top layer. */
		ret = -ETIMEDOUT;
	} else {
		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		BUG_ON(!hw_priv->wsm_cmd.done);
		ret = hw_priv->wsm_cmd.ret;
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);
	}
	{
		wsm_buf_reset(buf);
	}
	hw_priv->sbus_ops->power_mgmt(hw_priv->sbus_priv, true);
	return ret;
}

int wsm_cmd_send_no_ack(struct atbm_common *hw_priv,
		 struct wsm_buf *buf,
		 void *arg, u16 cmd, int if_id)
{
	struct sk_buff *skb;
	size_t buf_len = buf->data - buf->begin;
	struct wsm_hdr_tx * wsm_h = (struct wsm_hdr_tx *)buf->begin;
	int ret = 0;
	
	if(atbm_bh_is_term(hw_priv)){
		wsm_buf_reset(buf);
		return -3;
	}
	
	if (cmd == 0x0006) /* Write MIB */{
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "[WSM] >>> 0x%.4X [MIB: 0x%.4X] (%d)\n",
			cmd, __le16_to_cpu(((__le16 *)buf->begin)[sizeof(struct wsm_hdr_tx)/2]),
			buf_len);
	}
	else {
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "[WSM] >>> 0x%.4X (%d)\n", cmd, buf_len);
	}
 
	if (if_id == -1)
		if_id = 0;
	wsm_h = (struct wsm_hdr_tx *)buf->begin;

	wsm_h->len =__cpu_to_le16(buf_len);
	wsm_h->id =  __cpu_to_le16(cmd |(if_id << 6) );

	skb = atbm_dev_alloc_skb(hw_priv->extra_tx_headroom + buf_len);
	if (!skb)
		return -1;

	atbm_skb_reserve(skb, hw_priv->extra_tx_headroom);

	memcpy(atbm_skb_put(skb, buf_len), buf->begin, buf_len);
	atbm_skb_queue_tail(&hw_priv->tx_frame_queue, skb);
	wsm_buf_reset(buf);

	atbm_bh_wakeup(hw_priv);

	return ret;
}

/* ******************************************************************** */
/* WSM TX port control							*/

void wsm_lock_tx(struct atbm_common *hw_priv)
{
	wsm_cmd_lock(hw_priv);
	if (atomic_add_return(1, &hw_priv->tx_lock) == 1) {
		if (wsm_flush_tx(hw_priv))
			atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "[WSM] TX is locked.\n");
	}
	wsm_cmd_unlock(hw_priv);
}


void wsm_lock_tx_async(struct atbm_common *hw_priv)
{
	if (atomic_add_return(1, &hw_priv->tx_lock) == 1)
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "[WSM] TX is locked (async).\n");
}

void wsm_unlock_tx_async(struct atbm_common *hw_priv)
{
	 atomic_sub_return(1, &hw_priv->tx_lock);
}

bool wsm_flush_tx(struct atbm_common *hw_priv)
{
	return true;
}

bool wsm_vif_flush_tx(struct atbm_vif *priv)
{
	return true;
}


void wsm_unlock_tx(struct atbm_common *hw_priv)
{
	int tx_lock;
	if (hw_priv->bh_error){
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, KERN_ERR "fatal error occured, unlock is unsafe\n");
	}
	else {
		tx_lock = atomic_sub_return(1, &hw_priv->tx_lock);
		if (tx_lock < 0) {
			BUG_ON(1);
		} else if (tx_lock == 0) {
			atbm_bh_wakeup(hw_priv);
			atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, KERN_DEBUG "[WSM] TX is unlocked.\n");
		}
	}
}

/* ******************************************************************** */
/* WSM RX								*/

int wsm_handle_exception(struct atbm_common *hw_priv, u8 *data, u32 len)
{
	struct wsm_buf buf;
	u32 reason;
	u32 reg[18];
	char fname[32];
	int i;


	buf.begin = buf.data = data;
	buf.end = &buf.begin[len];

	reason = WSM_GET32(&buf);
	for (i = 0; i < ARRAY_SIZE(reg); ++i)
		reg[i] = WSM_GET32(&buf);
	WSM_GET(&buf, fname, sizeof(fname));


	atbm_printk_err("Firmware assert at %d,%s, line %d\n",
			(int)sizeof(fname), fname, (int)reg[1]);

	for (i = 0; i < 12; i += 4)
		atbm_printk_err("R%d: 0x%.8X, R%d: 0x%.8X, R%d: 0x%.8X, R%d: 0x%.8X,\n",
			i + 0, reg[i + 0], i + 1, reg[i + 1],
			i + 2, reg[i + 2], i + 3, reg[i + 3]);
	atbm_printk_err("R12: 0x%.8X, SP: 0x%.8X, LR: 0x%.8X, PC: 0x%.8X,\n",
		reg[i + 0], reg[i + 1], reg[i + 2], reg[i + 3]);
	i += 4;
	atbm_printk_err("CPSR: 0x%.8X, SPSR: 0x%.8X\n",
		reg[i + 0], reg[i + 1]);

	print_hex_dump_bytes("R1: ", DUMP_PREFIX_NONE,
		fname, sizeof(fname));

	atbm_wifi_run_status_set(1);
	return 0;

underflow:
	atbm_printk_err("Firmware exception.\n");
	print_hex_dump_bytes("Exception: ", DUMP_PREFIX_NONE,
		data, len);
	atbm_wifi_run_status_set(1);
	return -EINVAL;
}

#ifndef CONFIG_ATBM_SDIO_ATCMD
static int wsm_receive_indication(struct atbm_common *hw_priv,
					int interface_link_id,
					struct wsm_buf *buf,
					struct sk_buff **skb_p)
{
	struct atbm_vif *priv;
	struct wsm_rx rx;
	struct ieee80211_hdr *hdr;
	size_t hdr_len;
	__le16 fctl;

	rx.status = WSM_GET32(buf);
	rx.channelNumber = WSM_GET16(buf);
	rx.rxedRate = WSM_GET8(buf);
	rx.rcpiRssi = WSM_GET8(buf);
	rx.flags = WSM_GET32(buf);
	rx.channel_type = WSM_GET32(buf);
		
	rx.link_id = ((rx.flags & (0xf << 25)) >> 25);
	rx.if_id = interface_link_id;


	/* FW Workaround: Drop probe resp or
	beacon when RSSI is 0 */
	hdr = (struct ieee80211_hdr *) buf->data;
	priv = ABwifi_hwpriv_to_vifpriv(hw_priv, rx.if_id);
	if (!priv) {
		//printk(KERN_ERR "wsm_receive_indication: NULL priv drop frame(%d)\n",rx.if_id);
		return 0;
	}

	/* FW Workaround: Drop probe resp or
	beacon when RSSI is 0 */
#if (PROJ_TYPE>=ARES_A)
	if(rx.rcpiRssi > 128)
		rx.rcpiRssi = rx.rcpiRssi -256;
	else
		rx.rcpiRssi = rx.rcpiRssi;
#else //ATHEBNAB
	rx.rcpiRssi = rx.rcpiRssi / 2 - 110;
#endif //(PROJ_TYPE>=ARES_A)
	fctl = *(__le16 *)buf->data;
	hdr_len = buf->data - buf->begin;
	atbm_skb_pull(*skb_p, hdr_len);
	atbm_rx_cb(priv, &rx, skb_p);
	if (*skb_p)
		atbm_skb_push(*skb_p, hdr_len);
	rcu_read_unlock();
	return 0;

underflow:
	return -EINVAL;
}
#endif

static int wsm_startup_indication(struct atbm_common *hw_priv,
					struct wsm_buf *buf)
{
	u16 status;
	char fw_label[129];
	static const char * const fw_types[] = {
		"ETF",
		"WFM",
		"WSM",
		"HI test",
		"Platform test"
	};
	u32 Config[4];
	u16 firmwareCap2;

	hw_priv->wsm_caps.numInpChBufs	= WSM_GET16(buf);
	hw_priv->wsm_caps.sizeInpChBuf	= WSM_GET16(buf);
	hw_priv->wsm_caps.hardwareId	= WSM_GET16(buf);
	hw_priv->wsm_caps.hardwareSubId	= WSM_GET16(buf);
	status				= WSM_GET16(buf);
	hw_priv->wsm_caps.firmwareCap	= WSM_GET16(buf);
	atbm_printk_init("firmwareCap %x\n",hw_priv->wsm_caps.firmwareCap);
	hw_priv->wsm_caps.firmwareType	= WSM_GET16(buf);
	hw_priv->wsm_caps.firmwareApiVer	= WSM_GET16(buf);
	hw_priv->wsm_caps.firmwareBuildNumber = WSM_GET16(buf);
	hw_priv->wsm_caps.firmwareVersion	= WSM_GET16(buf);
	WSM_GET(buf, &fw_label[0], sizeof(fw_label) - 1);
	fw_label[sizeof(fw_label) - 1] = 0; /* Do not trust FW too much. */
	Config[0]	= WSM_GET32(buf);
	Config[1]	= WSM_GET32(buf);
	Config[2]	= WSM_GET32(buf);
	Config[3]	= WSM_GET32(buf);
	firmwareCap2 =WSM_GET16(buf);
	atbm_printk_init("firmwareCap2 %x\n",firmwareCap2);
	hw_priv->wsm_caps.firmwareCap	|= (firmwareCap2<<16);
	hw_priv->wsm_caps.NumOfHwXmitedAddr = Config[3];
	if (hw_priv->wsm_caps.firmwareCap&CAPABLITIES_SDIO_TX_LIST_CHECK){
		hw_priv->hw_xmits = Config[2];
		hw_priv->hw_bufs_free = Config[2];
	}
	else {
		hw_priv->hw_xmits = hw_priv->wsm_caps.numInpChBufs;
		hw_priv->hw_bufs_free = hw_priv->wsm_caps.numInpChBufs;
	}
	hw_priv->hw_bufs_free_init = hw_priv->hw_bufs_free;
//	BUG_ON(hw_priv->wsm_caps.NumOfHwXmitedAddr == 0);
//	printk("wsm_caps.firmwareCap %x firmware used %s-rate policy\n",hw_priv->wsm_caps.firmwareCap,hw_priv->wsm_caps.firmwareCap&CAPABILITIES_NEW_RATE_POLICY?"new":"old");
	atbm_printk_always("wsm_caps.firmwareCap %x",hw_priv->wsm_caps.firmwareCap);

	if (WARN_ON(status))
		return -EINVAL;

	if (WARN_ON(hw_priv->wsm_caps.firmwareType > 4))
		return -EINVAL;

	atbm_printk_always("apollo wifi WSM init done.\n"
		"   Input buffers: %d x %d bytes\n"
		"   Hardware: %d.%d\n"
		"   %s firmware [%s], ver: %d, build: %d,"
		" api: %d, cap: 0x%.4X Config[%x]  expection %x, tx prog %d\n",
		hw_priv->wsm_caps.numInpChBufs,
		hw_priv->wsm_caps.sizeInpChBuf,
		hw_priv->wsm_caps.hardwareId,
		hw_priv->wsm_caps.hardwareSubId,
		fw_types[hw_priv->wsm_caps.firmwareType],
		&fw_label[0],
		hw_priv->wsm_caps.firmwareVersion,
		hw_priv->wsm_caps.firmwareBuildNumber,
		hw_priv->wsm_caps.firmwareApiVer,
		hw_priv->wsm_caps.firmwareCap,Config[0],Config[1],hw_priv->hw_xmits);
		hw_priv->wsm_caps.firmwareReady = 1;
		hw_priv->wsm_caps.exceptionaddr =Config[1];
		//hw_priv->wsm_caps.HiHwCnfBufaddr = Config[2];//ep0 addr
#if 0	
	atbm_printk_init("CAPABILITIES_ATBM_PRIVATE_IE      [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_ATBM_PRIVATE_IE)		); 
	atbm_printk_init("CAPABILITIES_NVR_IPC              [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_NVR_IPC)  );  
	atbm_printk_init("CAPABILITIES_NO_CONFIRM           [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_NO_CONFIRM 		)  );
	atbm_printk_init("CAPABILITIES_SDIO_PATCH           [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_SDIO_PATCH 		)  );
	atbm_printk_init("CAPABILITIES_NO_BACKOFF           [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_NO_BACKOFF 		)  );
	atbm_printk_init("CAPABILITIES_CFO                  [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_CFO 		)  );  
	atbm_printk_init("CAPABILITIES_AGC                  [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_AGC 		)  );  
	atbm_printk_init("CAPABILITIES_TXCAL                [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_TXCAL 		)  );  
	atbm_printk_init("CAPABILITIES_MONITOR              [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_MONITOR 		)  );  
	atbm_printk_init("CAPABILITIES_CUSTOM               [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_CUSTOM 		)  );
	atbm_printk_init("CAPABILITIES_SMARTCONFIG          [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_SMARTCONFIG		)  );
	atbm_printk_init("CAPABILITIES_ETF                  [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_ETF		)  );
	atbm_printk_init("CAPABILITIES_LMAC_RATECTL         [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_LMAC_RATECTL		)  );  
	atbm_printk_init("CAPABILITIES_LMAC_TPC             [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_LMAC_TPC		)  );  
	atbm_printk_init("CAPABILITIES_LMAC_TEMPC           [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_LMAC_TEMPC		)  );  
	atbm_printk_init("CAPABILITIES_CTS_BUG              [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_CTS_BUG		)  );
	atbm_printk_init("CAPABILITIES_USB_RECOVERY_BUG     [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_USB_RECOVERY_BUG)	); 
	atbm_printk_init("CAPABILITIES_USE_IPC              [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_USE_IPC)      );
	atbm_printk_init("CAPABILITIES_OUTER_PA             [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_OUTER_PA)      );
	atbm_printk_init("CAPABILITIES_POWER_CONSUMPTION    [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_POWER_CONSUMPTION)      );
	atbm_printk_init("CAPABILITIES_RSSI_DECIDE_TXPOWER  [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_RSSI_DECIDE_TXPOWER)      );
	atbm_printk_init("CAPABILITIES_RTS_LONG_DURATION    [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_RTS_LONG_DURATION)      );
	atbm_printk_init("CAPABILITIES_TX_CFO_PPM_CORRECTION[%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_TX_CFO_PPM_CORRECTION)      );
	atbm_printk_init("CAPABILITIES_HW_CHECKSUM          [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_HW_CHECKSUM)      );
	atbm_printk_init("CAPABILITIES_SINGLE_CHANNEL_MULRX [%d]\n" ,!!(hw_priv->wsm_caps.firmwareCap &CAPABILITIES_SINGLE_CHANNEL_MULTI_RX)      );

#ifdef CONFIG_TX_NO_CONFIRM
	if((hw_priv->wsm_caps.firmwareCap &CAPABILITIES_NO_CONFIRM)==0){
		atbm_printk_init("LMAC NOT CAPABILITIES_NO_CONFIRM <ERROR>\n");
		BUG_ON(1);
	}
#else
	if((hw_priv->wsm_caps.firmwareCap &CAPABILITIES_NO_CONFIRM)){
		
		atbm_printk_init("LMAC SET CAPABILITIES_NO_CONFIRM <ERROR>\n");
		BUG_ON(1);
	}
#endif

#ifdef ATBM_P2P_ADDR_USE_LOCAL_BIT
	if((hw_priv->wsm_caps.firmwareCap &CAPABILITIES_VIFADDR_LOCAL_BIT)==0){
		
		atbm_printk_init("LMAC NOT CAPABILITIES_VIFADDR_LOCAL_BIT <ERROR>\n");
//		BUG_ON(1);
	}
#else
	if((hw_priv->wsm_caps.firmwareCap &CAPABILITIES_VIFADDR_LOCAL_BIT)){
		
		atbm_printk_init("LMAC SET CAPABILITIES_VIFADDR_LOCAL_BIT <ERROR>\n");
//		BUG_ON(1);
	}
#endif

#ifdef ATBM_PRODUCT_TEST_USE_FEATURE_ID
	atbm_printk_init("CONFIG_PRODUCT_TEST_USE_FEATURE_ID [1]\n");
#else
	atbm_printk_init("CONFIG_PRODUCT_TEST_USE_FEATURE_ID [0]\n");
#endif
#ifdef CONFIG_ATBM_PRODUCT_TEST_USE_GOLDEN_LED
	atbm_printk_init("CONFIG_PRODUCT_TEST_USE_GOLDEN_LED [1]\n");
#else
	atbm_printk_init("CONFIG_PRODUCT_TEST_USE_GOLDEN_LED [0]\n");
#endif
#endif
	if (((hw_priv->wsm_caps.firmwareVersion < 13549) && (strcmp(PRIV_VERSION, "2022-0104-1105")>=0))
		|| ((hw_priv->wsm_caps.firmwareVersion >= 13549) && (strcmp(PRIV_VERSION, "2022-0104-1105")<0)))
	{
		printk("ERROR !!! Unmatched firmwareVersion and driverVersion ...ERROR !!!\n");
		goto underflow;
	}

	return 0;

underflow:
	WARN_ON(1);
	return -EINVAL;
}
static int wsm_generic_confirm(struct atbm_common *hw_priv,
			     void *arg,
			     struct wsm_buf *buf)
{
	u32 status = WSM_GET32(buf);
	if (status != WSM_STATUS_SUCCESS){
		atbm_printk_err( "%s:status(%d)\n",__func__,status);
		return -EINVAL;
	}
	return 0;

underflow:
	WARN_ON(1);
	return -EINVAL;
}

int wsm_generic_get_confirm(struct atbm_common *hw_priv,
				struct wsm_generic_get_arg_s *arg, struct wsm_buf *buf)
{
	u8 *ret_buf = arg->buf;

	WSM_GET(buf, ret_buf, arg->buf_size);

	return 0;

underflow:
	WARN_ON(1);
	return -EINVAL;
}

int wsm_confirm_for_sdio_alive(struct atbm_common *hw_priv, struct wsm_buf *buf)
{
	u32 status = WSM_GET32(buf);
	u32 notify = WSM_GET32(buf);

	if (status == WSM_STATUS_SUCCESS && notify == 2121){
		return 0;
	}
	else {
		return -1;
	}

underflow:
	WARN_ON(1);
	return -EINVAL;
}

#ifdef CONFIG_ATBM_SDIO_ATCMD
static int wsm_atcmd_indication(struct atbm_common *hw_priv, struct wsm_buf *buf, int interface_link_id)
{
	int first;
	struct atbm_wsm_event *event = NULL;
	int len;

	event = atbm_kzalloc(sizeof(struct atbm_wsm_event), GFP_KERNEL);
	
	if(event == NULL){
		WARN_ON(1);
		return -1;
	}

	event->evt.eventId = WSM_EVENT_ATCMD_RECIVE;	
	
	//atbm_printk_init("buf->begin:%x, buf->data:%x, buf->end:%x\n",buf->begin,buf->data,buf->end);
	len = buf->end - buf->data;
	if(len > MAX_SDIO_EVENT_BUFFER_LEN){
		goto underflow;
	}
	memcpy(event->evt.buffer, (buf)->data, len);	

	event->if_id = interface_link_id;
	
	atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "[WSM] Event: %d\n",event->evt.eventId);
	spin_lock_bh(&hw_priv->event_queue_lock);
	first = list_empty(&hw_priv->event_queue);
	list_add_tail(&event->link, &hw_priv->event_queue);
	spin_unlock_bh(&hw_priv->event_queue_lock);
	
	if (first)
		atbm_hw_priv_queue_work(hw_priv, &hw_priv->event_handler);
	
	return 0;

underflow:
	if(event)
		atbm_kfree(event);
	return -EINVAL;
}
#endif

int wsm_handle_rx(struct atbm_common *hw_priv, int id,
		  struct wsm_hdr *wsm, struct sk_buff **skb_p)
{
	struct wsm_buf wsm_buf;
	int interface_link_id = (id >> 6) & 0x0F;
	int ret = 0;
	/* Strip link id. */
	id &= ~WSM_TX_LINK_ID(WSM_TX_LINK_ID_MAX);

	wsm_buf.begin = (u8 *)&wsm[0];
	wsm_buf.data = (u8 *)&wsm[1];
	wsm_buf.end = &wsm_buf.begin[__le32_to_cpu(wsm->len)];

	atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "[WSM][vid=%d] <<< 0x%.4X (%d)\n",interface_link_id, id,
			wsm_buf.end - wsm_buf.begin);
	
	if (id & WSM_CNF_BASE) {
		void *wsm_arg;
		u16 wsm_cmd;

		/* Do not trust FW too much. Protection against repeated
		 * response and race condition removal (see above). */
		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		wsm_arg = hw_priv->wsm_cmd.arg;
		wsm_cmd = hw_priv->wsm_cmd.cmd &
				~WSM_TX_LINK_ID(WSM_TX_LINK_ID_MAX);
		hw_priv->wsm_cmd.last_send_cmd=hw_priv->wsm_cmd.cmd = 0xFFFF;
		
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);
		
		if (WARN_ON((id & ~WSM_CNF_BASE) != wsm_cmd)) {
			/* Note that any non-zero is a fatal retcode. */
			ret = -EINVAL;
			goto out;
		}
		switch (id) {

		case 0x0400:
			if (likely(wsm_arg))
				ret = wsm_read_shmem_confirm(hw_priv,
									wsm_arg,
									&wsm_buf);
			break;
		case 0x0401:
			if (likely(wsm_arg))
				ret = wsm_write_shmem_confirm(hw_priv,
									wsm_arg,
									&wsm_buf);
			break;
			
		case WSM_CONFIG_RESP_ID:
		case WSM_SCAN_INFO_RESP_ID:
		case WSM_TCP_FILTER_GET_RESP_ID:
		case WSM_GET_COUNTRY_RESP_ID:
		case WSM_GET_STALIST_RESP_ID:
		case WSM_GET_VER_RESP_ID:
		case WSM_GET_SDK_VER_RESP_ID:
		case WSM_GET_AP_CFG_RESP_ID:
		case WSM_GET_RATE_RESP_ID:
		case WSM_GET_SCAN_STATE_RESP_ID:
		case WSM_GET_RSSI_RESP_ID:
		case WSM_GET_TIME_RESP_ID:
		case WSM_GET_ETF_RX_INFO_RESP_ID:
		case WSM_CONN_LOSE_RESP_ID:
		case WSM_DIRECT_TRANS_BUFFER_RESP_ID:
			if (likely(wsm_arg))
				ret = wsm_generic_get_confirm(hw_priv,
									wsm_arg,
									&wsm_buf);
			break;
			
		case WSM_JOIN_RESP_ID:
		case WSM_SCAN_RESP_ID:
		case WSM_WIFIMODE_RESP_ID:
		case WSM_CHANNEL_RESP_ID:
		case WSM_SET_COUNTRY_RESP_ID:
			break;

		case WSM_TCP_FILTER_RESP_ID: /* tcp filter */
		case WSM_PSMODE_RESP_ID:
		case WSM_AP_CFG_RESP_ID:
		case WSM_SMART_CFG_START_RESP_ID:
		case WSM_SMART_CFG_STOP_RESP_ID:
		case WSM_AP_TOUCH_START_RESP_ID:
		case WSM_AP_TOUCH_STOP_RESP_ID:
		case WSM_ETF_START_TX_RESP_ID:
		case WSM_ETF_SINGLE_TONE_RESP_ID:
		case WSM_ETF_STOP_TX_RESP_ID:
		case WSM_ETF_START_RX_RESP_ID:
		case WSM_ETF_STOP_RX_RESP_ID:
		case WSM_ETF_RESET_RX_RESP_ID:
		case WSM_ADAPTIVE_RESP_ID:
		case WSM_UPDATE_RESP_ID:
		case WSM_SET_LISTEN_ITVL_RESP_ID:
		case WSM_AT_CMD_RESP_ID:
		case WSM_SET_DBG_PRINT_RESP_ID:
		case WSM_ETF_START_RX_NO_DROP_RESP_ID:
		case WSM_FW_SLEEP_RESP_ID:
		case WSM_CLEAR_WIFI_CFG_RESP_ID:
		case WSM_ADD_CONN_PARAM_INFO_RESP_ID:
		case WSM_DEL_CONN_PARAM_INFO_RESP_ID:
		case WSM_ADD_NETPATTERN_INFO_RESP_ID:
		case WSM_DEL_NETPATTERN_INFO_RESP_ID:
		case WSM_CONN_SWITCH_RESP_ID:
		case WSM_SET_WK_SSID_RESP_ID:
		case WSM_CLEAR_WK_SSID_RESP_ID:
		case WSM_AUTO_RECONNECT_RESP_ID:
		case WSM_WAKEUP_EVENT_RESP_ID:
		case WSM_CUSTOMER_CMD_RESP_ID:
		case WSM_CUSTOMER_CERT_SAVE_RESP_ID:
		case WSM_FORCE_REBOOT_RESP_ID:
		case WSM_NETWORK_OK_RESP_ID:
		case WSM_HOST_REBOOT_NOTIFY_RESP_ID:
		case WSM_EXTEND_MSG_RESP_ID:
			WARN_ON(wsm_arg != NULL);
			ret = wsm_generic_confirm(hw_priv, wsm_arg, &wsm_buf);
			if (ret)
				atbm_printk_warn("wsm_generic_confirm "
					"failed for request 0x%.4X.\n",
					id & ~0x0400);
			break;
		case WSM_CHECK_ALIVE_RESP_ID:
			WARN_ON(wsm_arg != NULL);
			ret = wsm_confirm_for_sdio_alive(hw_priv, &wsm_buf);
			break;
		default:
			WARN_ON(wsm_arg != NULL);
			//ret = wsm_generic_confirm(hw_priv, wsm_arg, &wsm_buf);
			BUG_ON(1);
		}

		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		hw_priv->wsm_cmd.ret = ret;
		hw_priv->wsm_cmd.done = 1;
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);
		ret = 0; /* Error response from device should ne stop BH. */

		wake_up(&hw_priv->wsm_cmd_wq);
	} 
	else if (id & WSM_IND_BASE) {
		switch (id) {
		case WSM_STARTUP_IND_ID:
			ret = wsm_startup_indication(hw_priv, &wsm_buf);
			break;
		case WSM_EVENT_INDICATION_ID:
			ret = wsm_event_indication(hw_priv, &wsm_buf,interface_link_id);
			break;
		case WSM_RECEIVE_INDICATION_ID:
		case WSM_RECEIVE2_INDICATION_ID:
#ifndef CONFIG_ATBM_SDIO_ATCMD
			ret = wsm_receive_indication(hw_priv,interface_link_id,&wsm_buf,skb_p); 
#else
			WARN_ON(1);
			ret = -EINVAL;			
#endif
			break;
		case  WSM_TRACE_IND_ID:
			ret=0;
		default:
			//STUB();
			break;
		}
	}
#ifdef CONFIG_ATBM_SDIO_ATCMD
	else if(id & WSM_SDIO_ATCMD_BASE){
		switch (id) {
		case WSM_SDIO_ATCMD_DIRECT_ID:
			ret = wsm_atcmd_indication(hw_priv, &wsm_buf, interface_link_id);
			break;
		default:
			BUG_ON(1);
			break;
		}
	}
#endif
	else {
		WARN_ON(1);
		ret = -EINVAL;
	}
out:
	return ret;
}




int wsm_txed(struct atbm_common *hw_priv, u8 *data)
{
	if (data == hw_priv->wsm_cmd.ptr) {
		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		hw_priv->wsm_cmd.last_send_cmd = hw_priv->wsm_cmd.cmd;
		hw_priv->wsm_cmd.ptr = NULL;
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);;
		return  1;
	}
	return 0;
}

/* ******************************************************************** */
/* WSM buffer*/

void wsm_buf_init(struct wsm_buf *buf)
{
	BUG_ON(buf->begin);
	buf->begin = atbm_kmalloc(/*SDIO_BLOCK_SIZE*/ MAX_WSM_BUF_LEN, GFP_KERNEL | GFP_DMA);
	buf->end = buf->begin ? &buf->begin[MAX_WSM_BUF_LEN] : buf->begin;
	wsm_buf_reset(buf);
	//printk("%s hw_priv->wsm_cmd_buf begin 0x%x.data 0x%x \n",__func__,buf->begin,buf->data);

}

void wsm_buf_deinit(struct wsm_buf *buf)
{
	if(buf->begin)
		atbm_kfree(buf->begin);
	buf->begin = buf->data = buf->end = NULL;
}

static void wsm_buf_reset(struct wsm_buf *buf)
{
	if (buf->begin) {
		buf->data = &buf->begin[sizeof(struct wsm_hdr_tx)];
		*(u32 *)buf->begin = 0;
	}
	else
		buf->data = buf->begin;
}

static int wsm_buf_reserve(struct wsm_buf *buf, size_t extra_size)
{
	size_t pos = buf->data - buf->begin;
	size_t size = pos + extra_size;

	if (size & (SDIO_BLOCK_SIZE - 1)) {
		size &= SDIO_BLOCK_SIZE;
		size += SDIO_BLOCK_SIZE;
	}

	buf->begin = atbm_krealloc(buf->begin, size, GFP_KERNEL | GFP_DMA);
	if (buf->begin) {
		buf->data = &buf->begin[pos];
		buf->end = &buf->begin[size];
		return 0;
	} else {
		buf->end = buf->data = buf->begin;
		return -ENOMEM;
	}
}


int wsm_read_shmem(struct atbm_common *hw_priv, u32 address, void *buffer,
			size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	u16 flags = 0;//0x80|0x40;
	struct wsm_shmem_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT32(buf, address);
	WSM_PUT16(buf, buf_size);
	WSM_PUT16(buf, flags);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, 0x0000, WSM_CMD_TIMEOUT,
				0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_config(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_CONFIG_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_tcp_filter(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_TCP_FILTER_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}




int wsm_get_tcp_filter(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_TCP_FILTER_GET_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}


int wsm_set_psmode(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_PSMODE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_scan(struct atbm_common *hw_priv, struct wsm_scan_req *scan_req)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf, scan_req, sizeof(struct wsm_scan_req));
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SCAN_REQ_ID, WSM_CMD_TIMEOUT, 0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_scan_info(struct atbm_common *hw_priv, void *buffer, size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf, buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_SCAN_INFO_REQ_ID, WSM_CMD_TIMEOUT, 0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_wifimode(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_WIFIMODE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_ap_cfg(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_AP_CFG_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_wifichannel(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CHANNEL_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_countryId(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SET_COUNTRY_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_countryId(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_COUNTRY_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_stalist(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_STALIST_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_smart_cfg_start(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SMART_CFG_START_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_smart_cfg_stop(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SMART_CFG_STOP_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_ap_touch_start(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_AP_TOUCH_START_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_ap_touch_stop(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_AP_TOUCH_STOP_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_start_tx(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_START_TX_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_single_tone(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_SINGLE_TONE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_stop_tx(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_STOP_TX_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_start_rx(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_START_RX_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_start_rx_no_drop(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_START_RX_NO_DROP_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_stop_rx(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_STOP_RX_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_etf_reset_rx(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ETF_RESET_RX_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_adaptive(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ADAPTIVE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_ver(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_VER_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_sdk_ver(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_SDK_VER_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_update_fw(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_UPDATE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_ap_cfg(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_AP_CFG_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_listen_itvl(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SET_LISTEN_ITVL_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_send_at_cmd(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_AT_CMD_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_dbg_print(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SET_DBG_PRINT_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_fw_sleep(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_FW_SLEEP_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_tx_rate(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_RATE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_send_ipc_data(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf, buffer, buf_size);
	ret = wsm_cmd_send_no_ack(hw_priv, buf, NULL, WSM_IPC_DATA_REQ_ID, 0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_scan_state(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_SCAN_STATE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_rssi(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_RSSI_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_time(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_TIME_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_clear_wifi_config(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CLEAR_WIFI_CFG_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_get_etf_rx_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_GET_ETF_RX_INFO_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_add_netpattern_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ADD_NETPATTERN_INFO_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_del_netpattern_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_DEL_NETPATTERN_INFO_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_add_conn_param_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_ADD_CONN_PARAM_INFO_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_del_conn_param_info(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_DEL_CONN_PARAM_INFO_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_conn_switch(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CONN_SWITCH_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_conn_lose(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT16(buf, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_CONN_LOSE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_wakeup_ssid(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_SET_WK_SSID_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_clear_wakeup_ssid(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CLEAR_WK_SSID_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_auto_reconnect(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_AUTO_RECONNECT_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_set_wakeup_event(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_WAKEUP_EVENT_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_send_customer_cmd(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CUSTOMER_CMD_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_customer_cert_save(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CUSTOMER_CERT_SAVE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_check_alive(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_CHECK_ALIVE_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_direct_trans_buffer(struct atbm_common *hw_priv, void *buffer, size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_generic_get_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = buf_size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, WSM_DIRECT_TRANS_BUFFER_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_force_reboot(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_FORCE_REBOOT_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_host_reboot_notify(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_HOST_REBOOT_NOTIFY_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}


int wsm_host_network_ok_notify(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);

	if (hw_priv->wsm_caps.firmwareVersion >= 13679)
	{
		WSM_PUT(buf,buffer, buf_size);
		ret = wsm_cmd_send_no_ack(hw_priv, buf, NULL, WSM_NETWORK_OK_REQ_ID,0);
	}
	else 
	{
		ret = 0;
	}

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_ext_fast_cfg_recv(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_extend_msg_req extend_msg = {0};

	wsm_cmd_lock(hw_priv);

	extend_msg.externId = WSM_EXTEND_FAST_CFG_RECV_ID;
	WSM_PUT(buf, &extend_msg, sizeof(struct wsm_extend_msg_req));
	WSM_PUT(buf, buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_EXTEND_MSG_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_ext_fast_cfg_send(struct atbm_common *hw_priv, void *buffer,size_t buf_size)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	struct wsm_extend_msg_req extend_msg = {0};

	wsm_cmd_lock(hw_priv);

	extend_msg.externId = WSM_EXTEND_FAST_CFG_SEND_ID;
	WSM_PUT(buf, &extend_msg, sizeof(struct wsm_extend_msg_req));
	WSM_PUT(buf,buffer, buf_size);
	ret = wsm_cmd_send(hw_priv, buf, NULL, WSM_EXTEND_MSG_REQ_ID, WSM_CMD_TIMEOUT,0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}



#define HI_STATUS_SUCCESS (0)

int wsm_read_shmem_confirm(struct atbm_common *hw_priv,
				struct wsm_shmem_arg_s *arg, struct wsm_buf *buf)
{
	u8 *ret_buf = arg->buf;

	if (WARN_ON(WSM_GET32(buf) != HI_STATUS_SUCCESS))
		return -EINVAL;

	WSM_GET(buf, ret_buf, arg->buf_size);

	return 0;

underflow:
	WARN_ON(1);
	return -EINVAL;
}

int wsm_write_shmem(struct atbm_common *hw_priv, u32 address,size_t size,
						void *buffer)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;
	u16 flags = 0;//0x80|0x40;
	struct wsm_shmem_arg_s wsm_shmem_arg = {
		.buf = buffer,
		.buf_size = size,
	};

	wsm_cmd_lock(hw_priv);

	WSM_PUT32(buf, address);
	WSM_PUT16(buf, size);
	WSM_PUT16(buf, flags);
	WSM_PUT(buf, buffer, size);

	ret = wsm_cmd_send(hw_priv, buf, &wsm_shmem_arg, 0x0001, WSM_CMD_TIMEOUT,
				0);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_join(struct atbm_common *hw_priv, struct wsm_join *arg,
	     int if_id)
/*TODO: combo: make it work per vif.*/
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_oper_lock(hw_priv);
	wsm_cmd_lock(hw_priv);

	WSM_PUT(buf, arg, sizeof(struct wsm_join));

	hw_priv->tx_burst_idx = -1;
	ret = wsm_cmd_send(hw_priv, buf, arg, WSM_JOIN_REQ_ID, WSM_CMD_JOIN_TIMEOUT,
			   if_id);
	wsm_cmd_unlock(hw_priv);
	wsm_oper_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	wsm_oper_unlock(hw_priv);
	return -ENOMEM;
}
int wsm_configuration(struct atbm_common *hw_priv,
		      struct wsm_configuration *arg,
		      int if_id)
{
	int ret;
	struct wsm_buf *buf = &hw_priv->wsm_cmd_buf;

	wsm_cmd_lock(hw_priv);
	WSM_PUT32(buf, arg->dot11MaxTransmitMsduLifeTime);

	WSM_PUT32(buf, arg->dot11MaxReceiveLifeTime);
	WSM_PUT32(buf, arg->dot11RtsThreshold);


	/* DPD block. */
	WSM_PUT16(buf, arg->dpdData_size + 12);

	WSM_PUT16(buf, 1); /* DPD version */

	WSM_PUT(buf, arg->dot11StationId, ETH_ALEN);

	WSM_PUT16(buf, 5); /* DPD flags */

	WSM_PUT(buf, arg->dpdData, arg->dpdData_size);



	ret = wsm_cmd_send(hw_priv, buf, arg, WSM_CONFIGURATION_REQ_ID, WSM_CMD_TIMEOUT, if_id);

	wsm_cmd_unlock(hw_priv);
	return ret;

nomem:
	wsm_cmd_unlock(hw_priv);
	return -ENOMEM;
}

int wsm_write_shmem_confirm(struct atbm_common *hw_priv,
				struct wsm_shmem_arg_s *arg, struct wsm_buf *buf)
{
	if (WARN_ON(WSM_GET32(buf) != HI_STATUS_SUCCESS))
		return -EINVAL;
	return 0;

underflow:
	WARN_ON(1);
	return -EINVAL;
}

int wsm_get_tx(struct atbm_common *hw_priv, u8 **data,
	       u32 *tx_len, int *burst, int *vif_selected,struct sk_buff **pskb)
{
	/*
	 * Count was intended as an input for wsm->more flag.
	 * During implementation it was found that wsm->more
	 * is not usable, see details above. It is kept just
	 * in case you would like to try to implement it again.
	 */
	int count = 0;
	struct wsm_hdr_tx *wsm_tx=NULL;
	struct sk_buff *skb;
	*pskb = NULL;
	if (hw_priv->wsm_cmd.ptr) {
		++count;
		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		BUG_ON(!hw_priv->wsm_cmd.ptr);
		*data = hw_priv->wsm_cmd.ptr;
		wsm_tx = (struct wsm_hdr_tx *)hw_priv->wsm_cmd.ptr;
		*tx_len = hw_priv->wsm_cmd.len;
		*burst = 1;
		*vif_selected = -1;
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);		
	} else if((skb = atbm_skb_dequeue(&hw_priv->tx_frame_queue)) != NULL){
		wsm_tx = (struct wsm_hdr_tx *)skb->data;
		count ++;
		*data = skb->data;
		*tx_len = wsm_tx->len;
		*burst = 1;
		*vif_selected = 0;
		*pskb = skb;
	}
#ifdef CONFIG_ATBM_SDIO_ATCMD
	else if(hw_priv->at_cmd_get < hw_priv->at_cmd_put){
		BUG_ON(hw_priv->at_cmd_buf[hw_priv->at_cmd_get & (ATBM_AT_CMD_MAX_SW_CACHE - 1)] == NULL);
		wsm_tx = (struct wsm_hdr_tx *)hw_priv->at_cmd_buf[hw_priv->at_cmd_get & (ATBM_AT_CMD_MAX_SW_CACHE - 1)];
		*data = hw_priv->at_cmd_buf[hw_priv->at_cmd_get & (ATBM_AT_CMD_MAX_SW_CACHE - 1)];
		*tx_len = wsm_tx->len;
		*burst = 1;
		*vif_selected = 0;	
		count ++;
	}
#endif
	
	return count;
}

