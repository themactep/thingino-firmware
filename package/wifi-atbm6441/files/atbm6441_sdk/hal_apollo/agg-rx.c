/*
 * HT handling
 *
 * Copyright 2003, Jouni Malinen <jkmaline@cc.hut.fi>
 * Copyright 2002-2005, Instant802 Networks, Inc.
 * Copyright 2005-2006, Devicescape Software, Inc.
 * Copyright 2006-2007	Jiri Benc <jbenc@suse.cz>
 * Copyright 2007, Michael Wu <flamingice@sourmilk.net>
 * Copyright 2007-2010, Intel Corporation
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

/**
 * DOC: RX A-MPDU aggregation
 *
 * Aggregation on the RX side requires only implementing the
 * @ampdu_action callback that is invoked to start/stop any
 * block-ack sessions for RX aggregation.
 *
 * When RX aggregation is started by the peer, the driver is
 * notified via @ampdu_action function, with the
 * %IEEE80211_AMPDU_RX_START action, and may reject the request
 * in which case a negative response is sent to the peer, if it
 * accepts it a positive response is sent.
 *
 * While the session is active, the device/driver are required
 * to de-aggregate frames and pass them up one by one to mac80211,
 * which will handle the reorder buffer.
 *
 * When the aggregation session is stopped again by the peer or
 * ourselves, the driver's @ampdu_action function will be called
 * with the action %IEEE80211_AMPDU_RX_STOP. In this case, the
 * call must not fail.
 */
#ifdef LINUX_OS
#include <linux/ieee80211.h>
#include <linux/slab.h>
#include <linux/export.h>
#include <net/atbm_mac80211.h>
#endif
#include "apollo.h"
#include "ieee80211_i.h"
#include "bh.h"

void ieee80211_process_delba(struct atbm_vif *vif,
			     struct sta_info *sta,
			     struct atbm_ieee80211_mgmt *mgmt, size_t len)
{
	u16 tid, params;
	u16 initiator;

	params = le16_to_cpu(mgmt->u.action.u.delba.params);
	tid = (params & IEEE80211_DELBA_PARAM_TID_MASK) >> 12;
	initiator = (params & IEEE80211_DELBA_PARAM_INITIATOR_MASK) >> 11;
	if (initiator == WLAN_BACK_INITIATOR)
		__ieee80211_stop_rx_ba_session(sta, tid, WLAN_BACK_INITIATOR, 0,
					       true);
}
void ieee80211_sta_tear_down_BA_sessions(struct sta_info *sta, bool tx)
{
	int i;

	cancel_work_sync(&sta->ampdu_mlme.work);

	for (i = 0; i <  STA_TID_NUM; i++) {
		__ieee80211_stop_rx_ba_session(sta, i, WLAN_BACK_RECIPIENT,
					       WLAN_REASON_QSTA_LEAVE_QBSS, tx);
	}
}

static void ieee80211_free_tid_rx(struct rcu_head *h)
{
	struct tid_ampdu_rx *tid_rx =
		container_of(h, struct tid_ampdu_rx, rcu_head);
	int i;

	for (i = 0; i < tid_rx->buf_size; i++)
		atbm_dev_kfree_skb(tid_rx->reorder_buf[i]);
	atbm_kfree(tid_rx->reorder_buf);
	atbm_kfree(tid_rx->reorder_time);
	atbm_kfree(tid_rx);
}

void ___ieee80211_stop_rx_ba_session(struct sta_info *sta, u16 tid,
				     u16 initiator, u16 reason, bool tx)
{
	struct tid_ampdu_rx *tid_rx;

	lockdep_assert_held(&sta->ampdu_mlme.mtx);

	tid_rx = rcu_dereference_protected(sta->ampdu_mlme.tid_rx[tid],
					lockdep_is_held(&sta->ampdu_mlme.mtx));

	if (!tid_rx)
		return;

	RCU_INIT_POINTER(sta->ampdu_mlme.tid_rx[tid], NULL);

	atbm_del_timer_sync(&tid_rx->session_timer);
	atbm_del_timer_sync(&tid_rx->reorder_timer);

	call_rcu(&tid_rx->rcu_head, ieee80211_free_tid_rx);
}

void __ieee80211_stop_rx_ba_session(struct sta_info *sta, u16 tid,
				    u16 initiator, u16 reason, bool tx)
{
	mutex_lock(&sta->ampdu_mlme.mtx);
	___ieee80211_stop_rx_ba_session(sta, tid, initiator, reason, tx);
	mutex_unlock(&sta->ampdu_mlme.mtx);
}
/*
 * After accepting the AddBA Request we activated a timer,
 * resetting it after each frame that arrives from the originator.
 */
static void sta_rx_agg_session_timer_expired(unsigned long data)
{
	/* not an elegant detour, but there is no choice as the timer passes
	 * only one argument, and various sta_info are needed here, so init
	 * flow in sta_info_create gives the TID as data, while the timer_to_id
	 * array gives the sta through container_of */
	u8 *ptid = (u8 *)data;
	u8 *timer_to_id = ptid - *ptid;
	struct sta_info *sta = container_of(timer_to_id, struct sta_info,
					 timer_to_tid[0]);

#ifdef CONFIG_MAC80211_ATBM_HT_DEBUG
	atbm_printk_agg("rx session timer expired on tid %d\n", (u16)*ptid);
#endif
	set_bit(*ptid, sta->ampdu_mlme.tid_rx_timer_expired);
	atbm_hw_priv_queue_work(sta->hw_priv, &sta->ampdu_mlme.work);
}

static void sta_rx_agg_reorder_timer_expired(unsigned long data)
{
	u8 *ptid = (u8 *)data;
	u8 *timer_to_id = ptid - *ptid;
	struct sta_info *sta = container_of(timer_to_id, struct sta_info,
			timer_to_tid[0]);

	rcu_read_lock();
	ieee80211_release_reorder_timeout(sta, *ptid);
	rcu_read_unlock();
}
void ieee80211_process_addba_request(struct atbm_common *hw_priv,
				     struct sta_info *sta,
				     struct atbm_ieee80211_mgmt *mgmt,
				     size_t len)
{
	struct tid_ampdu_rx *tid_agg_rx;
	u16 capab, tid, timeout, ba_policy, buf_size, start_seq_num, status;
	u8 dialog_token;

	/* extract session parameters from addba request frame */
	dialog_token = mgmt->u.action.u.addba_req.dialog_token;
	timeout = le16_to_cpu(mgmt->u.action.u.addba_req.timeout);
	start_seq_num =
		le16_to_cpu(mgmt->u.action.u.addba_req.start_seq_num) >> 4;

	capab = le16_to_cpu(mgmt->u.action.u.addba_req.capab);
	ba_policy = (capab & IEEE80211_ADDBA_PARAM_POLICY_MASK) >> 1;
	tid = (capab & IEEE80211_ADDBA_PARAM_TID_MASK) >> 2;
	buf_size = (capab & IEEE80211_ADDBA_PARAM_BUF_SIZE_MASK) >> 6;

	status = WLAN_STATUS_REQUEST_DECLINED;

	if (test_sta_flag(sta, WLAN_STA_BLOCK_BA)) {
		goto end_no_lock;
	}

	/* sanity check for incoming parameters:
	 * check if configuration can support the BA policy
	 * and if buffer size does not exceeds max value */
	/* XXX: check own ht delayed BA capability?? */
	if (((ba_policy != 1) &&
	     (!(sta->sta.ht_cap.cap & IEEE80211_HT_CAP_DELAY_BA))) ||
	    (buf_size > IEEE80211_MAX_AMPDU_BUF)) {
		status = WLAN_STATUS_INVALID_QOS_PARAM;
		goto end_no_lock;
	}
	/* determine default buffer size */
	if (buf_size == 0)
		buf_size = IEEE80211_MAX_AMPDU_BUF;

	/* examine state machine */
	mutex_lock(&sta->ampdu_mlme.mtx);

	if (sta->ampdu_mlme.tid_rx[tid]) {
		/* delete existing Rx BA session on the same tid */
		___ieee80211_stop_rx_ba_session(sta, tid, WLAN_BACK_RECIPIENT,
						WLAN_STATUS_UNSPECIFIED_QOS,
						false);
	}

	/* prepare A-MPDU MLME for Rx aggregation */
	tid_agg_rx = atbm_kmalloc(sizeof(struct tid_ampdu_rx), GFP_KERNEL);
	if (!tid_agg_rx)
		goto end;

	spin_lock_init(&tid_agg_rx->reorder_lock);

	/* rx timer */
	tid_agg_rx->session_timer.function = sta_rx_agg_session_timer_expired;
	tid_agg_rx->session_timer.data = (unsigned long)&sta->timer_to_tid[tid];
	//init_timer(&tid_agg_rx->session_timer);
	atbm_init_timer(&tid_agg_rx->session_timer);

	/* rx reorder timer */
	tid_agg_rx->reorder_timer.function = sta_rx_agg_reorder_timer_expired;
	tid_agg_rx->reorder_timer.data = (unsigned long)&sta->timer_to_tid[tid];
	//init_timer(&tid_agg_rx->reorder_timer);
	atbm_init_timer(&tid_agg_rx->reorder_timer);
	
	/* prepare reordering buffer */
	tid_agg_rx->reorder_buf =
		atbm_kcalloc(buf_size, sizeof(struct sk_buff *), GFP_KERNEL);
	tid_agg_rx->reorder_time =
		atbm_kcalloc(buf_size, sizeof(unsigned long), GFP_KERNEL);
	if (!tid_agg_rx->reorder_buf || !tid_agg_rx->reorder_time) {
		atbm_kfree(tid_agg_rx->reorder_buf);
		atbm_kfree(tid_agg_rx->reorder_time);
		atbm_kfree(tid_agg_rx);
		goto end;
	}
	/* update data */
	tid_agg_rx->dialog_token = dialog_token;
	tid_agg_rx->ssn = start_seq_num;
	tid_agg_rx->head_seq_num = start_seq_num;
	tid_agg_rx->buf_size = buf_size;
	tid_agg_rx->timeout = timeout;
	tid_agg_rx->stored_mpdu_num = 0;
	status = WLAN_STATUS_SUCCESS;

	/* activate it for RX */
	rcu_assign_pointer(sta->ampdu_mlme.tid_rx[tid], tid_agg_rx);

	if (timeout)
		atbm_mod_timer(&tid_agg_rx->session_timer, TU_TO_EXP_TIME(timeout));

end:
	mutex_unlock(&sta->ampdu_mlme.mtx);

end_no_lock:
	return;
}
void ieee80211_ba_session_work(struct work_struct *work)
{
	struct sta_info *sta =
		container_of(work, struct sta_info, ampdu_mlme.work);
	int tid;

	/*
	 * When this flag is set, new sessions should be
	 * blocked, and existing sessions will be torn
	 * down by the code that set the flag, so this
	 * need not run.
	 */
	if (test_sta_flag(sta, WLAN_STA_BLOCK_BA))
		return;

	mutex_lock(&sta->ampdu_mlme.mtx);
	for (tid = 0; tid < STA_TID_NUM; tid++) {
		if (test_and_clear_bit(tid, sta->ampdu_mlme.tid_rx_timer_expired))
			___ieee80211_stop_rx_ba_session(
				sta, tid, WLAN_BACK_RECIPIENT,
				WLAN_REASON_QSTA_TIMEOUT, true);

		if (test_and_clear_bit(tid,
				       sta->ampdu_mlme.tid_rx_stop_requested))
			___ieee80211_stop_rx_ba_session(
				sta, tid, WLAN_BACK_RECIPIENT,
				WLAN_REASON_UNSPECIFIED, true);
	}
	mutex_unlock(&sta->ampdu_mlme.mtx);
}

