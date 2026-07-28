/*
 * Device handling thread implementation for mac80211 altobeam APOLLO drivers
 *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on:
 * Atbm UMAC CW1200 driver, which is
 * Copyright (c) 2010, ST-Ericsson
 * Author: Ajitpal Singh <ajitpal.singh@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */
//#undef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
#ifdef LINUX_OS
#include <net/atbm_mac80211.h>
#include <linux/kthread.h>
#endif

#include "apollo.h"
#include "bh.h"
#include "debug.h"
#include "hwio.h"
#include "wsm.h"
#include "sbus.h"
#include "apollo_plat.h"
#if defined(CONFIG_ATBM_APOLLO_BH_DEBUG)
#define bh_printk  atbm_printk_always
#else
#define bh_printk(...)
#endif
#define IS_SMALL_MSG(wsm_id) (wsm_id & 0x1000)
extern void atbm_monitor_pc(struct atbm_common *hw_priv);

int atbm_bh_read_ctrl_reg(struct atbm_common *hw_priv,
					  u16 *ctrl_reg);
int atbm_bh_read_ctrl_reg_unlock(struct atbm_common *hw_priv,
					  u16 *ctrl_reg);

static struct sk_buff *atbm_get_skb(struct atbm_common *hw_priv, u32 len);
int atbm_rx_tasklet(struct atbm_common *hw_priv, int id,
		  struct wsm_hdr *wsm, struct sk_buff **skb_p);

typedef int (*reed_ctrl_handler_t)(struct atbm_common *hw_priv,u16 *ctrl_reg);
typedef int (*reed_data_handler_t)(struct atbm_common *hw_priv, void *buf, u32 buf_len);

/* TODO: Verify these numbers with WSM specification. */
#define DOWNLOAD_BLOCK_SIZE_WR	(0x4000 - 4)
/* an SPI message cannot be bigger than (2"12-1)*2 bytes
 * "*2" to cvt to bytes */
#define MAX_SZ_RD_WR_BUFFERS	(DOWNLOAD_BLOCK_SIZE_WR*2)
#define PIGGYBACK_CTRL_REG	(2)
#define EFFECTIVE_BUF_SIZE	(MAX_SZ_RD_WR_BUFFERS - PIGGYBACK_CTRL_REG)
#define ATBM_MAX_OVERFLOW_SIZE	(64)
typedef int (*atbm_wsm_handler)(struct atbm_common *hw_priv,
	u8 *data, size_t size);

int atbm_register_bh(struct atbm_common *hw_priv)
{
	return 0;
}

/*
static void atbm_hw_buff_reset(struct atbm_common *hw_priv)
{
	hw_priv->wsm_tx_seq = 0;
	hw_priv->buf_id_tx = 0;
	hw_priv->wsm_rx_seq = 0;
	hw_priv->hw_bufs_used = 0;
	hw_priv->buf_id_rx = 0;
}
*/

void atbm_unregister_bh(struct atbm_common *hw_priv)
{
	return;
}
static int atbm_rx_directly(struct atbm_common *hw_priv,struct sk_buff *skb)
{
	u8 *data;
	struct wsm_hdr *wsm;
	u32 wsm_len;
	int wsm_id;
	u8 wsm_seq;
	static int rx_resync = 1;
	int status = 0;
	static int recv_cnt = 0;

	if (recv_cnt < 4) {//do not deal with first 4 invalid packets, soft reset bug
		wsm_seq = recv_cnt;
		hw_priv->wsm_rx_seq = (wsm_seq + 1) & 7;
		rx_resync = 0;
		recv_cnt++;
		atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "%s drop first 4 packets!\n", __func__); 
	}
	else {
		data = skb->data;
		wsm = (struct wsm_hdr *)data;
		
		wsm_len = __le32_to_cpu(wsm->len);
		wsm_id  = __le32_to_cpu(wsm->id) & 0x1FFF;
		wsm_seq = (__le32_to_cpu(wsm->id) >> 13) & 7;
		
		atbm_skb_trim(skb, wsm_len);
		if (unlikely(wsm_id == 0x0800)) {
			wsm_handle_exception(hw_priv,
				 &data[sizeof(*wsm)],
				wsm_len - sizeof(*wsm));
				status = -1;
				goto exit;
		} else if (unlikely(!rx_resync)) {
			if (WARN_ON(wsm_seq != hw_priv->wsm_rx_seq)) {
				atbm_printk_err("(wsm_seq %d != hw_priv->wsm_rx_seq %d) \n",wsm_seq , hw_priv->wsm_rx_seq);
				status = -2;
				goto exit;
			}
		}
		hw_priv->wsm_rx_seq = (wsm_seq + 1) & 7;
		rx_resync = 0;

		if (wsm_id & 0x0400) {
			int rc = wsm_release_tx_buffer(hw_priv, 1);
			if (WARN_ON(rc < 0)){
				status = -3;
				goto exit;
			}else if (rc > 0){
				atbm_bh_wakeup(hw_priv);
			}
		}
		/* atbm_wsm_rx takes care on SKB livetime */
		if (WARN_ON(atbm_rx_tasklet(hw_priv, wsm_id, wsm,
					  &skb))){
			status = -4;
			goto exit;
		}
	}
exit:
	if (skb) {
		atbm_dev_kfree_skb(skb);
	}
	return status;
}
#ifdef CONFIG_SDIO_IRQ_THREAD_PROCESS_DATA
static int atbm_sdio_submit_skb(struct atbm_common *hw_priv,struct sk_buff *skb)
{
	bool bh_running = false;
	__u32 queue_len = 0;
	
	spin_lock_bh(&hw_priv->rx_frame_queue.lock);
	__atbm_skb_queue_tail(&hw_priv->rx_frame_queue, skb);
	bh_running = hw_priv->bh_running;
	queue_len = atbm_skb_queue_len(&hw_priv->rx_frame_queue);
	spin_unlock_bh(&hw_priv->rx_frame_queue.lock);

	if (bh_running == true)
		;
	else if (hw_priv->sbus_ops->sbus_rev_schedule)
		hw_priv->sbus_ops->sbus_rev_schedule(hw_priv->sbus_priv);

	return (queue_len >= ATBM_MAX_OVERFLOW_SIZE) && (bh_running == false);
}
static int atbm_sdio_submit_skb_in_thread(struct atbm_common *hw_priv,struct sk_buff *skb)
{
	__u32 queue_len = 0;

	spin_lock_bh(&hw_priv->rx_frame_queue.lock);
	__atbm_skb_queue_tail(&hw_priv->rx_frame_queue, skb);
	queue_len = atbm_skb_queue_len(&hw_priv->rx_frame_queue);
	spin_unlock_bh(&hw_priv->rx_frame_queue.lock);

	return queue_len >= ATBM_MAX_OVERFLOW_SIZE;
}
#endif

static int atbm_sdio_process_read_data(struct atbm_common *hw_priv,reed_ctrl_handler_t read_ctrl_func,
	reed_data_handler_t read_data_func ,int (*rx_handle)(struct atbm_common *hw_priv,struct sk_buff *skb),enum atbm_rx_frame_type frame_type)
{
	#define LMAC_MAX_RX_BUFF	(24)
	u32 read_len_lsb = 0;
	u32 read_len_msb = 0;
	u32 read_len;
	struct sk_buff *skb_rx = NULL;
	u16 ctrl_reg = 0;
	u32 alloc_len;
	u8 *data;
	u8 rx_continue_cnt = 0;

	BUG_ON(read_ctrl_func == NULL);
	BUG_ON(read_data_func == NULL);
	BUG_ON(rx_handle == NULL);
rx_check:
	if (WARN_ON(read_ctrl_func(
			hw_priv, &ctrl_reg))){
			goto err;
	}
rx_continue:
	read_len_lsb = (ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_LSB_MASK)*2;
	read_len_msb = (ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_MSB_MASK)*2;
	read_len=((read_len_msb>>2)+read_len_lsb);
	if (!read_len) {
		return rx_continue_cnt;
	}

	if (WARN_ON((read_len < sizeof(struct wsm_hdr)) ||
			(read_len > EFFECTIVE_BUF_SIZE))) {
			atbm_printk_err("Invalid read len: %d,read_cnt(%d)\n",
				read_len,rx_continue_cnt);
		goto err;
	}
	/* Add SIZE of PIGGYBACK reg (CONTROL Reg)
	 * to the NEXT Message length + 2 Bytes for SKB */
	read_len = read_len + 2;
	alloc_len = read_len;
	if (alloc_len % SDIO_BLOCK_SIZE ) {
		alloc_len -= (alloc_len % SDIO_BLOCK_SIZE );
		alloc_len += SDIO_BLOCK_SIZE;
	}
	/* Check if not exceeding CW1200 capabilities */
	if (WARN_ON_ONCE(alloc_len > EFFECTIVE_BUF_SIZE)) {
		atbm_printk_err("Read aligned len: %d\n",
			alloc_len);
	}
	skb_rx = atbm_get_skb(hw_priv, alloc_len);
	if (WARN_ON(!skb_rx)){
		goto err;
	}

	atbm_skb_trim(skb_rx, 0);
	atbm_skb_put(skb_rx, read_len);
	data = skb_rx->data;
	
	if (WARN_ON(!data)){
		goto err;
	}
	
	if (WARN_ON(read_data_func(hw_priv, data, alloc_len))){
		goto err;
	}
	
	/* Piggyback */
	ctrl_reg = __le16_to_cpu(
		((__le16 *)data)[alloc_len / 2 - 1]);
	
	skb_rx->pkt_type = frame_type;
	rx_continue_cnt++;

	if(rx_handle(hw_priv,skb_rx) != 0){
		return rx_continue_cnt;
	}
	
	read_len_lsb = (ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_LSB_MASK)*2;
	read_len_msb = (ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_MSB_MASK)*2;
	read_len=((read_len_msb>>2)+read_len_lsb);
	
	if(read_len)
		goto rx_continue;
	goto rx_check;
	
	return rx_continue_cnt;
err:
	if(skb_rx)
		atbm_dev_kfree_skb(skb_rx);
	return -1;
}



static bool atbm_sdio_have_enough_space(struct atbm_common	*hw_priv,u32 n_needs)
{
	bool enough = false;
	
	enough = hw_priv->hw_bufs_free >= n_needs ? true : false;

	if(enough == false){
		
#ifdef CONFIG_TX_NO_CONFIRM
		u32 n_xmits = hw_priv->n_xmits;
		u32 hw_xmited = hw_priv->hw_xmits ;
		if(((int)(hw_xmited-n_xmits) > hw_priv->wsm_caps.numInpChBufs)) {
			atbm_printk_err("n_xmits %x|%x,hw_xmited %x numInpChBufs %d (hw_xmited-n_xmits) %d\n",hw_priv->n_xmits,n_xmits,hw_xmited, hw_priv->wsm_caps.numInpChBufs,(hw_xmited-n_xmits));
		}
		BUG_ON((int)(hw_xmited-n_xmits) > hw_priv->wsm_caps.numInpChBufs);
		//hw_priv->hw_xmits = hw_xmited;
		hw_priv->hw_bufs_free = (int)( hw_xmited - (n_xmits));
		hw_priv->hw_bufs_free_init = hw_priv->hw_bufs_free;
		enough = hw_priv->hw_bufs_free >= n_needs ? true : false;
#else //CONFIG_TX_CONFIRM
		hw_priv->hw_bufs_free = hw_priv->wsm_caps.numInpChBufs - hw_priv->hw_bufs_used;
		enough = hw_priv->hw_bufs_free >= n_needs ? true : false;
		hw_priv->hw_bufs_free_init = hw_priv->hw_bufs_free;
#endif //CONFIG_TX_NO_CONFIRM
	}

	return enough;
}

static bool atbm_sdio_wait_enough_space(struct atbm_common	*hw_priv,u32 n_needs)
{
#define MAX_LOOP_POLL_CNT  (2*3000)
	bool enough = false;
	int loop = 0;
	u32 print = 0;

	enough = hw_priv->hw_bufs_free >= n_needs ? true : false;
	
	while(enough == false){
		enough=atbm_sdio_have_enough_space(hw_priv,n_needs);
		if(enough == false){
			loop ++;
			if (hw_priv->close_driver)
				break;
			if(loop>=MAX_LOOP_POLL_CNT)
				break;
			if((loop >= 3)&&(print == 0)){			
				atbm_printk_debug("%s:n_xmits(%d),hw_xmited(%d),need(%d)\n",__func__,
					hw_priv->n_xmits,hw_priv->hw_xmits,n_needs);
				print = 1;
			}
#ifdef CONFIG_ATBM_SDIO_TX_HOLD
			hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
#endif //CONFIG_ATBM_SDIO_TX_HOLD
			schedule_timeout_interruptible(msecs_to_jiffies(2));
#ifdef CONFIG_ATBM_SDIO_TX_HOLD
			hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
#endif //CONFIG_ATBM_SDIO_TX_HOLD
		}
	}

	return enough;
}


static void atbm_sdio_force_free_wsm(struct atbm_common	*hw_priv,struct wsm_tx *wsm)
{
	int wsm_id;

	if(wsm == NULL)
		return;
	
	wsm_id = __le16_to_cpu(wsm->hdr.id) & 0x3F;

	switch(wsm_id){
	case WSM_FIRMWARE_CHECK_ID:
	case WSM_TRANSMIT_REQ_MSG_ID:
		wsm_release_tx_buffer(hw_priv, 1);
		break;
	default:
		wsm_release_tx_buffer(hw_priv, 1);
		spin_lock_bh(&hw_priv->wsm_cmd.lock);
		if(hw_priv->wsm_cmd.cmd != 0XFFFF){
			hw_priv->wsm_cmd.ret = -1;
			hw_priv->wsm_cmd.done = 1;
			hw_priv->wsm_cmd.cmd = 0xFFFF;
			hw_priv->wsm_cmd.ptr = NULL;
			hw_priv->wsm_cmd.arg = NULL;
			wake_up(&hw_priv->wsm_cmd_wq);		
		}	
		spin_unlock_bh(&hw_priv->wsm_cmd.lock);
		break;
	}
}

extern int is_pre_rmmod;

void atbm_sdio_tx_bh(struct atbm_common *hw_priv)
{
#ifdef  ATBM_WSM_SDIO_TX_MULT
#define WSM_SDIO_TX_MULT_BLOCK_SIZE	(6*SDIO_BLOCK_SIZE)
#else
#define WSM_SDIO_TX_MULT_BLOCK_SIZE	(SDIO_BLOCK_SIZE)
#endif
#define ATBM_SDIO_FREE_BUFF_ERR(condition,free,prev_free,xmiteds,hw_xmiteds)	\
	do{																			\
		if(condition)	{																\
			atbm_printk_err("%s[%d]:free(%x),prev_free(%x),xmiteds(%x),hw_xmiteds(%x)\n",__func__,__LINE__,free,prev_free,xmiteds,hw_xmiteds);	\
			BUG_ON(1);			\
		}\
	}while(0)
#ifdef CONFIG_TX_NO_CONFIRM
	static u8 loop = 1;
#else
	static u8 loop = 0;
#endif
	int tx_burst;
	struct wsm_hdr_tx *wsm_tx;
	int vif_selected;
	u32 tx_len=0;
	u8 *data;
	u8 *need_confirm = NULL;
	int ret=0;
	int txMutiFrameCount=0;
#if (PROJ_TYPE>=ARES_A)
	u32 wsm_flag_u32 = 0;
	u16 wsm_len_u16[2];
	u16 wsm_len_sum;
#endif	//	(PROJ_TYPE==ARES_A)	
	bool enough = false;
	struct sk_buff *skb = NULL;
	atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "%s enter...\n", __func__);
xmit_continue:
	if (hw_priv->close_driver){
		while((skb = atbm_skb_dequeue(&hw_priv->tx_frame_queue)) != NULL){
			//printk("free tx skb: %x\n", skb);
			atbm_dev_kfree_skb(skb);
		}
#ifdef CONFIG_ATBM_SDIO_ATCMD
		hw_priv->at_cmd_put = 0;
		hw_priv->at_cmd_get = 0;		
#endif
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "%s prepare close tx thread...\n", __func__);
		goto xmit_finished;
	}

	txMutiFrameCount = 0;
	hw_priv->xmit_buff_put = 0;
	enough = false;
	need_confirm = NULL;
	do {
		
		enough = atbm_sdio_have_enough_space(hw_priv,1);
		
		if(enough == false){
			if(txMutiFrameCount > 0)
				break;
			else
				goto xmit_wait;
		}
		ret = wsm_get_tx(hw_priv, &data, &tx_len, &tx_burst,&vif_selected,&skb);
		
		if (ret <= 0) {
			if(txMutiFrameCount > 0)
				break;
			else
				goto xmit_finished;
		}

		if (is_pre_rmmod){
			if (data != hw_priv->wsm_cmd.ptr){
				if(skb != NULL){
					atbm_dev_kfree_skb(skb);
					while((skb = atbm_skb_dequeue(&hw_priv->tx_frame_queue)) != NULL){
						//printk("prermmod free tx skb: %x\n", skb);
						atbm_dev_kfree_skb(skb);
					}
				}
#ifdef CONFIG_ATBM_SDIO_ATCMD
				hw_priv->at_cmd_put = 0;
				hw_priv->at_cmd_get = 0;				
#endif
				atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "%s prepare close tx thread, release tx packets...\n", __func__);
				goto xmit_finished;
			}
		}
		
		txMutiFrameCount++;
		wsm_tx = (struct wsm_hdr_tx *)data;
		BUG_ON(tx_len < sizeof(*wsm_tx));
		BUG_ON(__le32_to_cpu(wsm_tx->len) != tx_len);
		
#if (PROJ_TYPE>=ARES_A)
		wsm_flag_u32 = (tx_len) & 0xffff;
		wsm_len_u16[0] = wsm_flag_u32 & 0xff;
		wsm_len_u16[1] = (wsm_flag_u32 >> 8)& 0xff;
		wsm_len_sum = wsm_len_u16[0] + wsm_len_u16[1];
		if (wsm_len_sum & BIT(8)){
			wsm_flag_u32 |= ((wsm_len_sum + 1) & 0xff) << 24;
		}else {
			wsm_flag_u32 |= (wsm_len_sum & 0xff) << 24;
		}
		wsm_tx->flag=__cpu_to_le32(wsm_flag_u32);
#endif //(PROJ_TYPE==ARES_A)
		//atbm_printk_err("Write aligned len: %d,id %x\n", tx_len,wsm_tx->id);
		//dump_mem(wsm_tx,tx_len);
		if (tx_len <= 8)
			tx_len = 16;

		if (tx_len % (WSM_SDIO_TX_MULT_BLOCK_SIZE) ) {
			tx_len -= (tx_len % (WSM_SDIO_TX_MULT_BLOCK_SIZE) );
			tx_len += WSM_SDIO_TX_MULT_BLOCK_SIZE;
		}

		/* Check if not exceeding atbm
		capabilities */
		if (WARN_ON_ONCE(tx_len > EFFECTIVE_BUF_SIZE)) {
			atbm_printk_err("Write aligned len:"
			" %d\n", tx_len);
		}
		atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "%s wsm_tx id:[0x%x]\n", __func__, wsm_tx->id);
		wsm_tx->id &= __cpu_to_le32(~WSM_TX_SEQ(WSM_TX_SEQ_MAX));
		wsm_tx->id |= cpu_to_le32(WSM_TX_SEQ(hw_priv->wsm_tx_seq));
#ifdef  ATBM_WSM_SDIO_TX_MULT
		wsm_tx->tx_len = tx_len;
		wsm_tx->tx_id = wsm_tx->id;
#endif
		wsm_alloc_tx_buffer(hw_priv);

		ATBM_SDIO_FREE_BUFF_ERR(hw_priv->hw_bufs_free <= 0,hw_priv->hw_bufs_free,hw_priv->hw_bufs_free_init,hw_priv->n_xmits,hw_priv->hw_xmits);
		hw_priv->n_xmits ++;
		hw_priv->hw_bufs_free--;		
		ATBM_SDIO_FREE_BUFF_ERR(hw_priv->hw_bufs_free < 0,hw_priv->hw_bufs_free,hw_priv->hw_bufs_free_init,hw_priv->n_xmits,hw_priv->hw_xmits);

		atbm_xmit_linearize(hw_priv,(struct wsm_tx *)data,&hw_priv->xmit_buff[hw_priv->xmit_buff_put],wsm_tx->len,skb);
		hw_priv->xmit_buff_put += tx_len;
		hw_priv->wsm_tx_seq = (hw_priv->wsm_tx_seq + 1) & WSM_TX_SEQ_MAX;

		if(wsm_txed(hw_priv, data)){
			need_confirm = data;
			atbm_printk_always("%s:cmd free(%d),used(%d)\n",__func__,hw_priv->hw_bufs_free,hw_priv->hw_bufs_used);
			break;
		}else if(skb != NULL){
			need_confirm = NULL;
			#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
			spin_lock_irqsave(&hw_priv->tx_queue_lock, 0);
			#else
			spin_lock_bh(&hw_priv->tx_queue_lock);
			#endif
			hw_priv->tx_num_queued--;
			if (hw_priv->tx_queue_overfull && hw_priv->tx_num_queued <= (ATBM_WIFI_MAX_QUEUE_SZ/2)){
				hw_priv->tx_queue_overfull= false;
				#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
				spin_unlock_irqrestore(&hw_priv->tx_queue_lock, 0);
				#else
				spin_unlock_bh(&hw_priv->tx_queue_lock);
				#endif
#ifndef CONFIG_ATBM_SDIO_ATCMD
				netif_tx_wake_all_queues(hw_priv->vif_list[0]->ndev);
#endif
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
			//atbm_printk_always("%s: free tx buff\n",__func__);
			wsm_release_tx_buffer(hw_priv,1);
			hw_priv->wsm_txframe_num++;
		}
#ifdef CONFIG_ATBM_SDIO_ATCMD
		else{
			need_confirm = NULL;
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
			spin_lock_irqsave(&hw_priv->tx_queue_lock, 0);
#else
			spin_lock_bh(&hw_priv->tx_queue_lock);
#endif
			hw_priv->at_cmd_get ++;
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
			spin_unlock_irqrestore(&hw_priv->tx_queue_lock, 0);
#else
			spin_unlock_bh(&hw_priv->tx_queue_lock);
#endif
			//atbm_printk_always("%s: free tx buff\n",__func__);
			wsm_release_tx_buffer(hw_priv,1);
			hw_priv->wsm_txframe_num++;
		}
#endif	
		if (hw_priv->xmit_buff_put+hw_priv->wsm_caps.sizeInpChBuf>SDIO_TX_MAXLEN){
			break;
		}
	}while(loop);
	BUG_ON(hw_priv->xmit_buff_put == 0);
	hw_priv->buf_id_offset = txMutiFrameCount;
	
#ifdef CONFIG_ATBM_SDIO_TX_HOLD	
	if (WARN_ON(atbm_data_write_unlock(hw_priv,hw_priv->xmit_buff, hw_priv->xmit_buff_put))) {		
		atbm_printk_err("%s: xmit data err\n",__func__);
		goto xmit_err;
	}
#else
	if (WARN_ON(atbm_data_write(hw_priv,hw_priv->xmit_buff, hw_priv->xmit_buff_put))) {		
		atbm_printk_err("%s: xmit data err\n",__func__);
		goto xmit_err;
	}
#endif
xmit_wait:	
	if((enough == false)&&(atbm_sdio_wait_enough_space(hw_priv,1) == false)){
		atbm_printk_err("%s: wait space timeout\n",__func__);
		goto xmit_err;
	}
	
	goto xmit_continue;
	
xmit_finished:
	atbm_control_dbg(ATBM_CONTROL_DEBUG_TX, "%s exit...\n", __func__);
	return;
xmit_err:
	atbm_sdio_force_free_wsm(hw_priv,(struct wsm_tx *)need_confirm);
	goto xmit_continue;
}

void atbm_sdio_rx_bh(struct atbm_common *hw_priv)
{
	static bool hard_irq = true;
	atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "%s enter...\n", __func__); 
	if(hw_priv->hard_irq == false){
#ifdef CONFIG_SDIO_IRQ_THREAD_PROCESS_DATA	
		/*
		*irq bh has read the lmac packages
		*/
		struct sk_buff *skb;
		struct sk_buff_head local_list;		
		u16 ctrl_reg = 0;
		
		hard_irq = false;
		__atbm_skb_queue_head_init(&local_list);
		spin_lock_bh(&hw_priv->rx_frame_queue.lock);
		hw_priv->bh_running = true;
restart:
		atbm_skb_queue_splice_tail_init(&hw_priv->rx_frame_queue, &local_list);
		spin_unlock_bh(&hw_priv->rx_frame_queue.lock);

		while ((skb = __atbm_skb_dequeue(&local_list)) != NULL){
			atbm_rx_directly(hw_priv,skb);
		}


		ctrl_reg = 0;
		/*
		*the operation of reading reg can clear irq
		*/
		hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
		atbm_bh_read_ctrl_reg_unlock(hw_priv, &ctrl_reg);
		if(ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_MASK){
			atbm_sdio_process_read_data(hw_priv,atbm_bh_read_ctrl_reg_unlock,
										atbm_data_read_unlock,atbm_sdio_submit_skb_in_thread,ATBM_RX_RAW_FRAME);
		}
		hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);

		
		spin_lock_bh(&hw_priv->rx_frame_queue.lock);
		if(!atbm_skb_queue_empty(&hw_priv->rx_frame_queue))
			goto restart;
		hw_priv->bh_running = false;
		spin_unlock_bh(&hw_priv->rx_frame_queue.lock);
		atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "%s exit1...\n", __func__);
		return;
#endif
	}else {
		WARN_ON(hard_irq == false);
	}
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	atbm_sdio_process_read_data(hw_priv,atbm_bh_read_ctrl_reg,atbm_data_read,atbm_rx_directly,ATBM_RX_DERICTLY_DATA_FRAME);	
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	atbm_control_dbg(ATBM_CONTROL_DEBUG_RX, "%s exit...\n", __func__);
}

#ifdef CONFIG_ATBM_SDIO_ATCMD
void atbm_sdio_atcmd_buf_init(struct atbm_common *hw_priv)
{
	int i;
	
	for(i=0; i<ATBM_AT_CMD_MAX_SW_CACHE; i++){
		hw_priv->at_cmd_buf[i] = atbm_kzalloc(MAX_WSM_BUF_LEN, GFP_KERNEL | GFP_DMA);
		BUG_ON(hw_priv->at_cmd_buf[i] == NULL);
	}
	hw_priv->at_cmd_get = 0;
	hw_priv->at_cmd_put = 0;
}
#endif

void atbm_irq_handler(struct atbm_common *hw_priv)
{
	/* To force the device to be always-on, the host sets WLAN_UP to 1 */

	if(!hw_priv->init_done){
		//atbm_printk_err("[BH] irq. init_done =0 drop\n");
		u16 val16;
		atbm_reg_read_16_unlock(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, &val16);
		return;
	}

	if (atbm_bh_is_term(hw_priv))
		return;
	
	hw_priv->hard_irq = !in_interrupt() ? false : true;
	if(hw_priv->hard_irq == false)	{
		int rx_counter = 0;

#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
		hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
#endif
		__atbm_irq_enable(hw_priv,0);
#if (ATBM_WIFI_PLATFORM == PLATFORM_ANKAI_RTOS)
		hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
#endif
rx_continue:
#ifdef CONFIG_SDIO_IRQ_THREAD_PROCESS_DATA
		rx_counter = atbm_sdio_process_read_data(hw_priv,atbm_bh_read_ctrl_reg_unlock,atbm_data_read_unlock,
									atbm_sdio_submit_skb,ATBM_RX_RAW_FRAME);
#else 
		rx_counter = 0;
#endif
		if(rx_counter == 0){
			/*
			*triger rx to make sure that we can not miss irq
			*/
			atbm_printk_debug("%s:no package triger rx\n",__func__);
			goto triger_rx;
		}else if(rx_counter >= ATBM_MAX_OVERFLOW_SIZE){
			hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
			atbm_printk_debug("%s:over flow\n",__func__);
			schedule_timeout_interruptible(msecs_to_jiffies(10));			
			hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
			goto rx_continue;
		}
		return;
	}
triger_rx:	
	if(hw_priv->sbus_ops->sbus_rev_schedule)
		hw_priv->sbus_ops->sbus_rev_schedule(hw_priv->sbus_priv);
	return;
}

int atbm_bh_suspend(struct atbm_common *hw_priv)
{
	int ret = 0;
	
	if(hw_priv->sbus_ops->sbus_bh_suspend)
		ret = hw_priv->sbus_ops->sbus_bh_suspend(hw_priv->sbus_priv);

	return ret;
}

int atbm_bh_resume(struct atbm_common *hw_priv)
{
	int ret = 0;

	atbm_printk_pm("[BH] try resume.\n");

	if(hw_priv->sbus_ops->sbus_bh_resume)
		ret = hw_priv->sbus_ops->sbus_bh_resume(hw_priv->sbus_priv);
	return ret;
}

void wsm_alloc_tx_buffer(struct atbm_common *hw_priv)
{
	++hw_priv->hw_bufs_used;
}

int wsm_release_tx_buffer(struct atbm_common *hw_priv, int count)
{
	int ret = 0;
	int hw_bufs_used;
	hw_bufs_used = hw_priv->hw_bufs_used;
	hw_priv->hw_bufs_used -= count;

	if (WARN_ON(hw_priv->hw_bufs_used < 0))
		//ret = -1;
		hw_priv->hw_bufs_used=0;
	/* Tx data patch stops when all but one hw buffers are used.
	   So, re-start tx path in case we find hw_bufs_used equals
	   numInputChBufs - 1.
	 */
	else if (hw_bufs_used >= (hw_priv->wsm_caps.numInpChBufs - 1))
		ret = 1;
	return ret;
}

static struct sk_buff *atbm_get_skb(struct atbm_common *hw_priv, u32 len)
{
	struct sk_buff *skb;
	u32 alloc_len = (len > SDIO_BLOCK_SIZE) ? len : SDIO_BLOCK_SIZE;

	if (len > SDIO_BLOCK_SIZE || !hw_priv->skb_cache) {
		skb = __atbm_dev_alloc_skb(alloc_len
				+ WSM_TX_EXTRA_HEADROOM
				+ 8  /* TKIP IV */
				+ 12 /* TKIP ICV + MIC */
				- 2  /* Piggyback */,GFP_KERNEL);
		BUG_ON(skb==NULL);
		/* In AP mode RXed SKB can be looped back as a broadcast.
		 * Here we reserve enough space for headers. */
		atbm_skb_reserve(skb, WSM_TX_EXTRA_HEADROOM
				+ 8 /* TKIP IV */
				- WSM_RX_EXTRA_HEADROOM);
	} else {
		skb = hw_priv->skb_cache;
		hw_priv->skb_cache = NULL;
	}
	return skb;
}


void atbm_put_skb(struct atbm_common *hw_priv, struct sk_buff *skb)
{
	if (hw_priv->skb_cache){
		//printk("%s atbm_kfree_skb skb=%p\n",__func__,skb);
		atbm_dev_kfree_skb(skb);
	}
	else
		hw_priv->skb_cache = skb;
}

extern int is_pre_rmmod;

int atbm_bh_read_ctrl_reg(struct atbm_common *hw_priv,
					  u16 *ctrl_reg)
{
	int ret=0,retry=0;
	if (is_pre_rmmod && (hw_priv->wsm_caps.firmwareVersion>=13549)){
		return 0;
	}
	while (retry <= MAX_RETRY) {
		ret = atbm_reg_read_16(hw_priv,
				ATBM_HIFREG_CONTROL_REG_ID, ctrl_reg);
		if(!ret){
				break;
		}else{
			/*reset sdio internel reg by send cmd52 to abort*/
			WARN_ON(hw_priv->sbus_ops->abort(hw_priv->sbus_priv));
			retry++;
			mdelay(retry);
			atbm_printk_err(
				"[BH] Failed to read control register.ret=%x\n",ret);
		}
	}
	return ret;
}

int atbm_bh_read_ctrl_reg_unlock(struct atbm_common *hw_priv,
					  u16 *ctrl_reg)
{
	int ret=0,retry=0;
	if (is_pre_rmmod && (hw_priv->wsm_caps.firmwareVersion>=13549)){
		return 0;
	}
	while (retry <= MAX_RETRY) {
		ret = atbm_reg_read_16_unlock(hw_priv,
				ATBM_HIFREG_CONTROL_REG_ID, ctrl_reg);
		if(!ret){
				break;
		}else{
			/*reset sdio internel reg by send cmd52 to abort*/
			WARN_ON(hw_priv->sbus_ops->abort(hw_priv->sbus_priv));
			retry++;
			mdelay(retry);
			atbm_printk_err(
				"[BH] Failed to read control register.ret=%x\n",ret);
		}
	}
	return ret;
}

//just ARESB have this function
//used this function to clear sdio rtl bug register
// if not do this sdio direct mode (wr/read reigster) will not work
// this function is the same to atbm_data_force_write (used queue mode clear bit to clear)
// 
int atbm_powerave_sdio_sync(struct atbm_common *hw_priv)
{
	int ret=0;
	//int retry=0;
	u32 config_reg;
	ret = atbm_reg_read_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &config_reg);
	if (ret < 0) {
		atbm_printk_err("%s: enable_irq: can't read config register.\n", __func__);
	}

	if(config_reg & ATBM_HIFREG_PS_SYNC_SDIO_FLAG)
	{
		atbm_printk_err("%s:%d\n",__func__,__LINE__);
		//atbm_hw_buff_reset(hw_priv);
		config_reg |= ATBM_HIFREG_PS_SYNC_SDIO_CLEAN;
		atbm_reg_write_unlock_32(hw_priv,ATBM_HIFREG_CONFIG_REG_ID,config_reg);
	}
	return ret;
}

int rxMutiCnt[17]={0};
int rxCnt=0;
int rxMutiCnt_Num;
unsigned long g_printf_count = 0;
int atbm_rx_tasklet(struct atbm_common *hw_priv, int id,
		  struct wsm_hdr *wsm, struct sk_buff **skb_p)
{
	struct sk_buff *skb = *skb_p;
	struct sk_buff *atbm_skb_copy;
	//struct wsm_hdr *wsm;
	u32 wsm_len;
	int wsm_id;
	int data_len;
	int ret=0;
#define RX_ALLOC_BUFF_OFFLOAD (  (40+16)/*RX_DESC_OVERHEAD*/ -16 /*WSM_HI_RX_IND*/)

		wsm_len = __le32_to_cpu(wsm->len);
		wsm_id	= __le32_to_cpu(wsm->id) & 0x1FFF;
		if((wsm_id == WSM_MULTI_RECEIVE_INDICATION_ID)||
			(WSM_SINGLE_CHANNEL_MULTI_RECEIVE_INDICATION_ID == wsm_id)){
			struct wsm_multi_rx *  multi_rx = (struct wsm_multi_rx *)skb->data;			
			int RxFrameNum = multi_rx->RxFrameNum;
			
			data_len = wsm_len ;
			data_len -= sizeof(struct wsm_multi_rx);
			#ifdef LINUX_OS
			rxMutiCnt[ALIGN(wsm_len,1024)/1024]++;
			#else
			rxMutiCnt[ALIGN2(wsm_len,1024)/1024]++;
			#endif
			rxMutiCnt_Num+=RxFrameNum;
			wsm = (struct wsm_hdr *)(multi_rx+1);
			wsm_len = __le32_to_cpu(wsm->len);
			wsm_id	= __le32_to_cpu(wsm->id) & 0x1FFF;
			
			//frame_hexdump("dump sdio wsm rx ->",wsm,32);
			do {

				if(data_len < wsm_len){
					atbm_printk_err("skb->len %x,wsm_len %x data_len %x\n",skb->len,wsm_len,data_len);
					//frame_hexdump("dump sdio wsm rx ->",skb->data,64);
					break;
				}
				WARN_ON((wsm_id  & (~WSM_TX_LINK_ID(WSM_TX_LINK_ID_MAX))) !=  WSM_RECEIVE_INDICATION_ID);
				atbm_skb_copy = __atbm_dev_alloc_skb(wsm_len + 16,GFP_KERNEL);
				BUG_ON(atbm_skb_copy == NULL);
				atbm_skb_reserve(atbm_skb_copy,  (8 - (((unsigned long)atbm_skb_copy->data)&7))/*ALIGN 8*/);
				atbm_skb_copy->pkt_type = skb->pkt_type;
				memmove(atbm_skb_copy->data, wsm, wsm_len);
				atbm_skb_put(atbm_skb_copy,wsm_len);
				ret=wsm_handle_rx(hw_priv,wsm_id,wsm,&atbm_skb_copy);
				if(ret){
					rxMutiCnt_Num=0;
					memset(rxMutiCnt,0,sizeof(rxMutiCnt));
					if(atbm_skb_copy != NULL){
						atbm_dev_kfree_skb(atbm_skb_copy);
					}
					return ret;
				}
				#ifdef LINUX_OS
				data_len -= ALIGN(wsm_len + RX_ALLOC_BUFF_OFFLOAD,4);
				#else
				data_len -= ALIGN2(wsm_len + RX_ALLOC_BUFF_OFFLOAD,4);
				#endif
				RxFrameNum--;
				#ifdef LINUX_OS
				wsm = (struct wsm_hdr *)((u8 *)wsm +ALIGN(( wsm_len + RX_ALLOC_BUFF_OFFLOAD),4));
				#else
				wsm = (struct wsm_hdr *)((u8 *)wsm +ALIGN2(( wsm_len + RX_ALLOC_BUFF_OFFLOAD),4));
				#endif
				wsm_len = __le32_to_cpu(wsm->len);
				wsm_id	= __le32_to_cpu(wsm->id) & 0x1FFF;
				
				if(atbm_skb_copy != NULL){
					atbm_dev_kfree_skb(atbm_skb_copy);
				}
			}while((RxFrameNum>0) && (data_len > 32));
			BUG_ON(RxFrameNum != 0);
			
		}
		else {
			//rxMutiCnt[ALIGN(wsm_len,1024)/1024]++;
			rxCnt++;
			ret=wsm_handle_rx(hw_priv,id,wsm,skb_p);
		}
		return ret;

}
