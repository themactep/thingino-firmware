
#include <net/atbm_mac80211.h>
#include <linux/kthread.h>

#include "apollo.h"
#include "bh.h"
#include "bh_usb.h"
#include "wsm.h"
#include "sbus.h"
#include "debug.h"
#include "apollo_plat.h"
#include "sta.h"
#include "ap.h"
#include "scan.h"
#include "hwio_spi.h"

#if defined(CONFIG_ATBM_APOLLO_BH_DEBUG)
#define bh_printk  atbm_printk_always
#else
#define bh_printk(...)
#endif
static int spi_atbm_bh(void *arg);
void atbm_monitor_pc(struct atbm_common *hw_priv);
void atbm_spi_read_rdy_start(void);
void atbm_spi_read_rdy_end(void);


int atbm_register_bh(struct atbm_common *hw_priv)
{
	int err = 0;
	struct sched_param param = { .sched_priority = 1 };
	bh_printk( "[BH] register.\n");
	BUG_ON(hw_priv->bh_thread);
	atomic_set(&hw_priv->bh_rx, 0);
	atomic_set(&hw_priv->bh_tx, 0);
	atomic_set(&hw_priv->bh_term, 0);
	atomic_set(&hw_priv->hw_ready, 0);
	atomic_set(&hw_priv->bh_suspend, ATBM_APOLLO_BH_RESUMED);
	hw_priv->buf_id_tx = 0;
	hw_priv->buf_id_rx = 0;
	init_waitqueue_head(&hw_priv->bh_wq);
	init_waitqueue_head(&hw_priv->bh_evt_wq);

	hw_priv->bh_thread = kthread_create(&spi_atbm_bh, hw_priv, "spi_atbm_bh");

	if (IS_ERR(hw_priv->bh_thread)) {
		err = PTR_ERR(hw_priv->bh_thread);
		hw_priv->bh_thread = NULL;
	} else {
		WARN_ON(sched_setscheduler(hw_priv->bh_thread,
			SCHED_FIFO, &param));
#ifdef HAS_PUT_TASK_STRUCT
		get_task_struct(hw_priv->bh_thread);
#endif
		wake_up_process(hw_priv->bh_thread);
	}
	return err;
}

void atbm_unregister_bh(struct atbm_common *hw_priv)
{
	struct task_struct *thread = hw_priv->bh_thread;
	if (WARN_ON(!thread))
		return;
	
	hw_priv->bh_thread = NULL;
	bh_printk( "[BH] unregister.\n");
	atomic_add(1, &hw_priv->bh_term);
	wake_up(&hw_priv->bh_wq);
	kthread_stop(thread);
#ifdef HAS_PUT_TASK_STRUCT
	put_task_struct(thread);
#endif
}

int atbm_reset_driver(struct atbm_common *hw_priv)
{
	return 0;
}
int atbm_reset_lmc_cpu(struct atbm_common *hw_priv)
{
	return 0;
}

int atbm_bh_suspend(struct atbm_common *hw_priv)
{

	bh_printk( "[BH] suspend.\n");
	if (hw_priv->bh_error) {
		wiphy_warn(hw_priv->hw->wiphy, "BH error -- can't suspend\n");
		return -EINVAL;
	}

	atomic_set(&hw_priv->bh_suspend, ATBM_APOLLO_BH_SUSPEND);
	wake_up(&hw_priv->bh_wq);
	return atbm_wait_event_timeout_stay_awake(hw_priv,hw_priv->bh_evt_wq, hw_priv->bh_error ||
		(ATBM_APOLLO_BH_SUSPENDED == atomic_read(&hw_priv->bh_suspend)),
		 1 * HZ,false) ? 0 : -ETIMEDOUT;
}

int atbm_bh_resume(struct atbm_common *hw_priv)
{

	bh_printk( "[BH] resume.\n");
	if (hw_priv->bh_error) {
		wiphy_warn(hw_priv->hw->wiphy, "BH error -- can't resume\n");
		return -EINVAL;
	}

	atomic_set(&hw_priv->bh_suspend, ATBM_APOLLO_BH_RESUME);
	wake_up(&hw_priv->bh_wq);

	return atbm_wait_event_timeout_stay_awake(hw_priv,hw_priv->bh_evt_wq,hw_priv->bh_error ||
		(ATBM_APOLLO_BH_RESUMED == atomic_read(&hw_priv->bh_suspend)),
		1 * HZ,false) ? 0 : -ETIMEDOUT;

}

void wsm_alloc_tx_buffer(struct atbm_common *hw_priv)
{
	++hw_priv->hw_bufs_used;
}

int wsm_release_tx_buffer(struct atbm_common *hw_priv, int count)
{
	int ret = 0;

	hw_priv->hw_bufs_used -= count;
	ret = 1;
	return ret;
}


int atbm_spi_rx_bh_cb(struct atbm_common *hw_priv,struct sk_buff *skb)
{
	struct wsm_hdr *wsm;
	u32 wsm_len;
	int wsm_id;
	u8 wsm_seq;


	wsm = (struct wsm_hdr *)skb->data;

	wsm_len = __le32_to_cpu(wsm->len);

	wsm_id	= __le32_to_cpu(wsm->id) & 0x1FFF;
	wsm_seq = (__le32_to_cpu(wsm->id) >> 13) & 7;


	atbm_skb_trim(skb,0);
	atbm_skb_put(skb,wsm_len);

	if (unlikely(wsm_id == 0x0800)) {
		wsm_handle_exception(hw_priv,
			 &skb->data[sizeof(*wsm)],
			wsm_len - sizeof(*wsm));
		hw_priv->bh_error = 1;
		goto __free;
	}

	//printk( "rxcb len %x,id %x\n",wsm_len,wsm->id);
	if (WARN_ON(wsm_seq != hw_priv->wsm_rx_seq)) {
		atbm_printk_err("%s wsm_seq error %d %d \n",__func__,wsm_seq,hw_priv->wsm_rx_seq);
		goto __free;
	}
	hw_priv->wsm_rx_seq = (wsm_seq + 1) & 7;


	//frame_hexdump("dump  wsm rx ->",wsm,32);
	if (wsm_id & 0x0400) {
		int rc = wsm_release_tx_buffer(hw_priv, 1);
		if (WARN_ON(rc < 0))
			goto __free;
	}

	/* atbm_wsm_rx takes care on SKB livetime */
	if (WARN_ON(wsm_handle_rx(hw_priv, wsm_id, wsm,&skb))){
		atbm_printk_err("%s %d \n",__func__,__LINE__);
		goto __free;
	}

__free:
	if(skb != NULL){
		atbm_dev_kfree_skb(skb);
	}

	return 0;
}

static struct sk_buff *atbm_spi_get_skb(struct atbm_common *hw_priv, u32 len)
{
	struct sk_buff *skb;
	u32 alloc_len = (len > SPI_READ_BLOCK_SIZE) ? len : SPI_READ_BLOCK_SIZE;

	skb = atbm_dev_alloc_skb(alloc_len
			+ WSM_TX_EXTRA_HEADROOM
			+ 8  /* TKIP IV */
			+ 12 /* TKIP ICV + MIC */
			- 2  /* Piggyback */);
	/* In AP mode RXed SKB can be looped back as a broadcast.
	 * Here we reserve enough space for headers. */
	atbm_skb_reserve(skb, WSM_TX_EXTRA_HEADROOM
			+ 8 /* TKIP IV */
			- WSM_RX_EXTRA_HEADROOM);
	
	return skb;
}


static void atbm_spi_put_skb(struct atbm_common *hw_priv, struct sk_buff *skb)
{
	atbm_dev_kfree_skb(skb);
}


int atbm_spi_rx_bh(struct atbm_common *hw_priv)
{
	struct sk_buff *skb = 0;
	struct wsm_hdr *wsm;
	u32 wsm_len = 0;
	u32 status = 0;
	int ret = 0;
	int count = 0;
	u32 read_len = 0;
	u32 alloc_len = 0;
	u8 *data = 0;
	u32 ready = 0;
	u32 totalLen = 0;

	//printk("atbm_spi_rx_bh start\n");
	ret = atbm_read_status_ready(hw_priv, &ready);
	bh_printk( "spiRxBh ready=%d\n", ready);
	if ((ready == 0))
	{
		goto out;
	}

nextfrag:
	ret = atbm_read_status(hw_priv, &status);
	if ((ret != 0))//rx_ready
	{
		atbm_printk_err( "[BH] read status rx not ready\n");
		goto out;
	}
	bh_printk( "%s %d\n", __func__, __LINE__);

	read_len = SPI_RX_DATA_LENGTH(status);
	if (!read_len) {
		goto out;
	}
	read_len *= 4;

	if (WARN_ON(read_len < sizeof(struct wsm_hdr))) {
		atbm_printk_err( "Invalid read len: %d",
			read_len);
		goto out;
	}
	if (totalLen == 0)
	{
		alloc_len = 4000;

		skb = atbm_spi_get_skb(hw_priv, alloc_len);
		if (WARN_ON(!skb))
			goto error;

		atbm_skb_trim(skb, 0);
		atbm_skb_put(skb, read_len);
		data = skb->data;
		if (WARN_ON(!data))
			goto error;

	}
	
	//printk("atbm_spi_rx_bh start read_len:%d\n", read_len);
	if (WARN_ON(atbm_read_data(hw_priv, data + totalLen, read_len)))
		goto error;
	if (totalLen == 0)
	{
		wsm = (struct wsm_hdr *)data;
		wsm_len = __le32_to_cpu(wsm->len);
	}
	
	atbm_printk_bus("atbm_spi_rx_bh start wsm_len:%d, read_len:%d\n", wsm_len, read_len);
{
	int i;
	for (i = 0; i < 28; i++)
	{
		atbm_printk_bus("%02x ", data[i]);
	}
	atbm_printk_bus("\n");
}
	
	totalLen += read_len;
	if (wsm_len > totalLen)
	{
readyflagchange:
		
		msleep(500);
		ret = atbm_read_status_ready(hw_priv, &ready);
		if (ret !=0)
		{
			atbm_printk_bus( "[BH]RX SPI read status error.\n");
			goto error;
		}
		if (ready == 0)
		{
			atbm_printk_bus("atbm_spi_rx_bh start readyflagchange cout=%d\n", count);
			msleep(100);
			count++;
			if (count > 100)
			{	
				atbm_printk_err("[BH]RX SPI read status ready count > 100 error.\n");
				goto error;
			}
			goto readyflagchange;
		}else
		{
			msleep(600);
			atbm_printk_bus("atbm_spi_rx_bh start nextfrag\n");
			goto nextfrag;
		}
	}
	//printk("atbm_spi_rx_bh_cb start \n");

	atbm_spi_rx_bh_cb(hw_priv,skb);
out:
	return 0;
error:
	if (!skb)
		atbm_spi_put_skb(hw_priv,skb);
	return 0;
}

static int atbm_spi_xmit_data(struct atbm_common *hw_priv)
{
	int status=0;
	int tx_burst=0;
	int vif_selected;
	struct wsm_hdr_tx *wsm;
	u8 *data =NULL;
	int tx_len=0;
	int ret = 0;
	u32 chanflag = 0;
	u32 totalLen = 0;
	int count = 0;

	ret = atbm_read_status_channelflag(hw_priv, &chanflag);
	if ((ret !=0) || (chanflag == 0))
	{
		goto error;
	}

	if (hw_priv->device_can_sleep) {
			hw_priv->device_can_sleep = false;
	}

	wsm_alloc_tx_buffer(hw_priv);
	ret = wsm_get_tx(hw_priv, &data, &tx_len, &tx_burst, &vif_selected);
	if (ret <= 0) {
		  bh_printk( "%s __LINE__ %d wsm_get_tx null\n",__func__,__LINE__);
		  wsm_release_tx_buffer(hw_priv, 1);
		  status=-3;
		  goto error;
	} else {
		wsm = (struct wsm_hdr_tx *)data;
		BUG_ON(tx_len < sizeof(*wsm));
		BUG_ON(__le32_to_cpu(wsm->len) != tx_len);
		atomic_add(1, &hw_priv->bh_tx);

		wsm->id &= __cpu_to_le32(~WSM_TX_SEQ(WSM_TX_SEQ_MAX));
		wsm->id |= cpu_to_le32(WSM_TX_SEQ(hw_priv->wsm_tx_seq));
#if 0
		if (tx_len % SPI_WRITE_BLOCK_SIZE ) {
			tx_len -= (tx_len % SPI_WRITE_BLOCK_SIZE );
			tx_len += SPI_WRITE_BLOCK_SIZE;
		}
#endif
nextflag:
		
		ret = atbm_update_status_channelflag(hw_priv);	
		if ((ret !=0))
		{
			wsm_release_tx_buffer(hw_priv, 1);
			status=-4;
			bh_printk( "[BH] SPI update_status_channelflag error.\n");
			goto error;
		}
		
		{
			int i;
			
			atbm_printk_bus("tx prev\n");
			for (i = 0; i < 28; i++)
			{
				atbm_printk_bus("%02x ", data[i]);
			}
			atbm_printk_bus("\n");
		}
		
		bh_printk("[TX] WSM:id=0x%x,txlen %d,seq %x , totalLen=%d\n",wsm->id,tx_len,hw_priv->wsm_tx_seq , totalLen);
		if (WARN_ON(atbm_write_data(hw_priv,data + totalLen, SPI_WRITE_BLOCK_SIZE))) {
			wsm_release_tx_buffer(hw_priv, 1);
			goto error;
		}
		{
			int i;
			
			atbm_printk_bus("tx after\n");
			for (i = 0; i < 28; i++)
			{
				atbm_printk_bus("%02x ", data[i]);
			}
			atbm_printk_bus("\n");
		}

		totalLen += SPI_WRITE_BLOCK_SIZE;
		if (tx_len > totalLen)
		{
flagchange:
			ret = atbm_read_status_channelflag(hw_priv, &chanflag);
			if ((ret !=0))
			{
				atbm_printk_bus( "[BH] SPI read_status_channelflag error.\n");
				wsm_release_tx_buffer(hw_priv, 1);
				status=-5;
				goto error;
			}
			if (chanflag == 0)
			{
				count++;
				if (count > 10)
				{	
					wsm_release_tx_buffer(hw_priv, 1);
					status=-6;
					atbm_printk_bus( "[BH]TX SPI channelflag count > 10 error.\n");
					goto error;
				}
				msleep(600);
				goto flagchange;
			}else
			{
				msleep(600);
				goto nextflag;
			}
		}

		if (vif_selected != -1) {
			hw_priv->hw_bufs_used_vif[vif_selected]++;
		}

		if(wsm_txed(hw_priv, data)==0){
			hw_priv->wsm_txframe_num++;
		}

		hw_priv->wsm_tx_seq = (hw_priv->wsm_tx_seq + 1)	& WSM_TX_SEQ_MAX;

	}
	
error:
	return status;
}

static int spi_atbm_bh(void *arg)
{
	struct atbm_common *hw_priv = arg;
	struct atbm_vif *priv = NULL;
	int rx, tx=0, term, suspend, hw_ready;
	int pending_tx = 0;
	long status;
	bool powersave_enabled;
	int i;
	int prink_test =0;

	status = wait_event_interruptible_timeout(hw_priv->bh_wq, ({
				term = atomic_xchg(&hw_priv->bh_term, 0);
				hw_ready = atomic_xchg(&hw_priv->hw_ready, 0);
				(hw_ready || term || hw_priv->bh_error);
			}), HZ*50);
	if (status <= 0 || term || hw_priv->bh_error){
		atbm_printk_bus("%s BH thread break %ld %d %d\n",__func__,status,term,hw_priv->bh_error);
		goto out;
	}
	
#define __ALL_HW_BUFS_USED (hw_priv->hw_bufs_used)


	while (1) {

		powersave_enabled = 1;
		atbm_hw_vif_read_lock(&hw_priv->vif_list_lock);
		atbm_for_each_vif_safe(hw_priv, priv, i) {
			if (!priv)
				continue;
			powersave_enabled &= !!priv->powersave_enabled;
		}
		atbm_hw_vif_read_unlock(&hw_priv->vif_list_lock);

		if (!__ALL_HW_BUFS_USED
				&& powersave_enabled
				&& !hw_priv->device_can_sleep) {
			status = HZ*10;
			bh_printk( "[BH] No Device wakedown.\n");

		} else if (__ALL_HW_BUFS_USED)
			status = HZ;
		else
			status = HZ*10;

		//printk("spi_atbm_bh atbm_spi_read_rdy_start++\n");
		atbm_spi_read_rdy_start();
		//printk("spi_atbm_bh atbm_spi_read_rdy_start 2 ++%d\n",status/HZ);
		status = wait_event_interruptible_timeout(hw_priv->bh_wq, ({
				rx = atomic_xchg(&hw_priv->bh_rx, 0);
				tx = atomic_xchg(&hw_priv->bh_tx, 0);
				term = atomic_xchg(&hw_priv->bh_term, 0);
				suspend = pending_tx ?
					0 : atomic_read(&hw_priv->bh_suspend);
				(rx || tx || term || suspend || hw_priv->bh_error);
			}), status);

		atbm_spi_read_rdy_end();
		//printk("spi_atbm_bh atbm_spi_read_rdy_start end\n");

		if (status < 0 || term || hw_priv->bh_error){
			atbm_printk_err("%s BH thread break %ld %d %d\n",__func__,status,term,hw_priv->bh_error);
			break;
		}


		if (!status && __ALL_HW_BUFS_USED)
		{
			unsigned long timestamp = jiffies;
			long timeout;
			bool pending = false;
			int i;

			//wiphy_warn(hw_priv->hw->wiphy, "Missed interrupt?\n");
			rx = 1;
			/* Get a timestamp of "oldest" frame */
			for (i = 0; i < 4; ++i)
				pending |= atbm_queue_get_xmit_timestamp(
						&hw_priv->tx_queue[i],
						&timestamp, -1,
						hw_priv->pending_frame_id);

			/* Check if frame transmission is timed out.
			 * Add an extra second with respect to possible
			 * interrupt loss. */
			timeout = timestamp +
					WSM_CMD_LAST_CHANCE_TIMEOUT +
					1 * HZ  -
					jiffies;
			

			/* And terminate BH tread if the frame is "stuck" */
			if (pending && timeout < 0) {
				//wiphy_warn(priv->hw->wiphy,
				//	"Timeout waiting for TX confirm.\n");
				prink_test++;
				if(prink_test <10){
					atbm_printk_bus("atbm_bh: Timeout waiting for TX confirm. hw_bufs_used %d\n",hw_priv->hw_bufs_used);
				}
				//break;
			}
		} else if (!status) {
			atbm_printk_bus("%s %d ++ !!\n",__func__,__LINE__);
			if (!hw_priv->device_can_sleep) {
				bh_printk( "[BH] Device wakedown. Timeout.\n");
			}
			continue;
		} else if (suspend) {
			atbm_printk_bus( "[BH] Device suspend.\n");
			atbm_printk_bus("%s %d ++ !!\n",__func__,__LINE__);
			powersave_enabled = 1;
			atbm_hw_vif_read_lock(&hw_priv->vif_list_lock);
			atbm_for_each_vif_safe(hw_priv, priv, i) {
				if (!priv)
					continue;
				powersave_enabled &= !!priv->powersave_enabled;
			}
			atbm_hw_vif_read_unlock(&hw_priv->vif_list_lock);
			if (powersave_enabled) {
				bh_printk( "[BH] No Device wakedown. Suspend.\n");
			}

			atomic_set(&hw_priv->bh_suspend, ATBM_APOLLO_BH_SUSPENDED);
			wake_up(&hw_priv->bh_evt_wq);
			status = wait_event_interruptible(hw_priv->bh_wq,
					ATBM_APOLLO_BH_RESUME == atomic_read(
						&hw_priv->bh_suspend));
			if (status < 0) {
				wiphy_err(hw_priv->hw->wiphy,
					"%s: Failed to wait for resume: %ld.\n",
					__func__, status);
				break;
			}
			atbm_printk_bus( "[BH] Device resume.\n");
			atomic_set(&hw_priv->bh_suspend, ATBM_APOLLO_BH_RESUMED);
			//wake_up(&hw_priv->bh_evt_wq);
			//atomic_add(1, &hw_priv->bh_rx);
			continue;
		}
		if (rx){
			atbm_spi_rx_bh(hw_priv);
		}
		if (tx){
			atbm_spi_xmit_data(hw_priv);
	    }
	}
out:
	if (!term) {
		int loop = 3;
		atbm_printk_bus("%s %d ++ !!\n",__func__,__LINE__);
		atbm_dbg(ATBM_APOLLO_DBG_ERROR, "[BH] Fatal error, exitting.\n");

		hw_priv->bh_error = 1;
		while(loop-->0){
			atbm_monitor_pc(hw_priv);
			msleep(10);
		}
		
		atbm_hw_vif_read_lock(&hw_priv->vif_list_lock);
		atbm_for_each_vif_safe(hw_priv, priv, i) {
			if (!priv)
				continue;
			//ieee80211_driver_hang_notify(priv->vif, GFP_KERNEL);
		}
		atbm_hw_vif_read_unlock(&hw_priv->vif_list_lock);
#ifdef CONFIG_PM
		atbm_pm_stay_awake(&hw_priv->pm_state, 3*HZ);
#endif
		/* TODO: schedule_work(recovery) */
#ifndef HAS_PUT_TASK_STRUCT
		/* The only reason of having this stupid code here is
		 * that __put_task_struct is not exported by kernel. */
		for (;;) {
			int status = wait_event_interruptible(hw_priv->bh_wq, ({
				term = atomic_xchg(&hw_priv->bh_term, 0);
				(term);
				}));

			if (status || term)
				break;
		}
#endif
	}
	atbm_printk_bus("atbm_wifi_BH_thread stop ++\n");
	/*
	add this code just because 'linux kernel' need kthread not exit ,
	before kthread_stop func call,
	*/
	while(term){
		if(kthread_should_stop()){
			break;
		}
		schedule_timeout_uninterruptible(msecs_to_jiffies(100));
	}
	atbm_printk_bus("atbm_wifi_BH_thread stop --\n");
	return 0;
}


