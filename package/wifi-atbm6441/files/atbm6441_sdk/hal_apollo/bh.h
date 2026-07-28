/*
 * Device handling thread interface for mac80211 altobeam APOLLO drivers
 *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef ATBM_APOLLO_BH_H
#define ATBM_APOLLO_BH_H

/* extern */ struct atbm_common;

#define SDIO_BLOCK_SIZE 256

/* Suspend state privates */
enum atbm_bh_pm_state {
        ATBM_APOLLO_BH_RESUMED = 0,
        ATBM_APOLLO_BH_SUSPEND,
        ATBM_APOLLO_BH_SUSPENDED,
        ATBM_APOLLO_BH_RESUME,
};
enum atbm_rx_frame_type{
	ATBM_RX_RAW_FRAME = 1,
	ATBM_RX_DERICTLY_DATA_FRAME,
	ATBM_RX_SLOW_MGMT_FRAME,
	ATBM_RX_WSM_CMD_FRAME,
	ATBM_RX_WSM_DATA_FRAME,
	ATBM_RX_WSM_FREE,
};
//#include "bh_usb.h"

#ifdef CONFIG_ATBM_SDIO_ATCMD
void atbm_sdio_atcmd_buf_init(struct atbm_common *hw_priv);
#endif

int atbm_register_bh(struct atbm_common *hw_priv);
void atbm_unregister_bh(struct atbm_common *hw_priv);
void atbm_irq_handler(struct atbm_common *hw_priv);
void atbm_bh_wakeup(struct atbm_common *hw_priv);
int atbm_bh_suspend(struct atbm_common *hw_priv);
int atbm_bh_resume(struct atbm_common *hw_priv);
/* Must be called from BH thread. */
void atbm_enable_powersave(struct atbm_common *hw_priv,
			     bool enable);
int wsm_release_tx_buffer(struct atbm_common *hw_priv, int count);
void wsm_alloc_tx_buffer(struct atbm_common *hw_priv);
int wsm_release_vif_tx_buffer(struct atbm_common *hw_priv, int if_id,
				int count);
void atbm_put_skb(struct atbm_common *hw_priv, struct sk_buff *skb);

int atbm_powerave_sdio_sync(struct atbm_common *hw_priv);
int atbm_device_wakeup(struct atbm_common *hw_priv);
int atbm_device_sleep(struct atbm_common *hw_priv);
static inline int atbm_bh_is_term(struct atbm_common *hw_priv){	
	return 0;
}
#define can_not_queue_work(hw_priv) 					\
	(((hw_priv)->workqueue==NULL))
#define atbm_hw_priv_queue_work(hw_priv,work)		\
	(can_not_queue_work(hw_priv) ? -1:queue_work((hw_priv)->workqueue,work))
#define atbm_hw_priv_queue_delayed_work(hw_priv,dwork,delay)	\
	(can_not_queue_work(hw_priv) ? -1:queue_delayed_work((hw_priv)->workqueue,dwork,delay))
static inline bool atbm_cancle_queue_work(struct work_struct *work,bool sync)
{
	bool retval = false;
	if((sync == true) || work_pending(work))
	{
		retval = cancel_work_sync(work);
	}

	return retval;
}

static inline bool atbm_cancle_delayed_work(struct delayed_work *dwork,bool sync)
{
	bool retval = false;
	if(sync == true)
	{
		retval = cancel_delayed_work_sync(dwork);
	}
	else
	{
		retval = cancel_delayed_work(dwork);
	}

	return retval;
}
#ifdef CONFIG_PM
#define atbm_hold_suspend(__hw_priv)		atbm_pm_stay_awake_lock(&((__hw_priv)->pm_state))
#define atbm_release_suspend(__hw_priv)		atbm_pm_stay_awake_unlock(&((__hw_priv)->pm_state))
#else
#define atbm_hold_suspend(__hw_priv)		BUG_ON(__hw_priv==NULL)
#define atbm_release_suspend(__hw_priv)		BUG_ON(__hw_priv==NULL)
#endif

#define atbm_wait_event_timeout_stay_awake(_hw_priv,_wait_q,_cond,_timeout,_awake)	\
({																					\
	long ret_timeout = _timeout;													\
	if(_awake == true)	atbm_hold_suspend(_hw_priv);								\
	ret_timeout = wait_event_timeout(_wait_q,_cond,ret_timeout);					\
	if(_awake == true)	atbm_release_suspend(_hw_priv);								\
	ret_timeout;																	\
})
#endif /* ATBM_APOLLO_BH_H */
