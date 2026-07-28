/*
 * Copyright 2002-2005, Instant802 Networks, Inc.
 * Copyright 2006-2007	Jiri Benc <jbenc@suse.cz>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifdef LINUX_OS
#include <linux/module.h>
#include <linux/init.h>
#include <linux/netdevice.h>
#include <linux/types.h>
#include <linux/slab.h>
#include <linux/skbuff.h>
#include <linux/if_arp.h>
#include <linux/timer.h>
#include <linux/rtnetlink.h>

#include <net/atbm_mac80211.h>
#endif
#include "apollo.h"
#include "ieee80211_i.h"
#include "sta_info.h"


/**
 * DOC: STA information lifetime rules
 *
 * STA info structures (&struct sta_info) are managed in a hash table
 * for faster lookup and a list for iteration. They are managed using
 * RCU, i.e. access to the list and hash table is protected by RCU.
 *
 * Upon allocating a STA info structure with sta_info_alloc(), the caller
 * owns that structure. It must then insert it into the hash table using
 * either sta_info_insert() or sta_info_insert_rcu(); only in the latter
 * case (which acquires an rcu read section but must not be called from
 * within one) will the pointer still be valid after the call. Note that
 * the caller may not do much with the STA info before inserting it, in
 * particular, it may not start any mesh peer link management or add
 * encryption keys.
 *
 * When the insertion fails (sta_info_insert()) returns non-zero), the
 * structure will have been freed by sta_info_insert()!
 *
 * Station entries are added by mac80211 when you establish a link with a
 * peer. This means different things for the different type of interfaces
 * we support. For a regular station this mean we add the AP sta when we
 * receive an association response from the AP. For IBSS this occurs when
 * get to know about a peer on the same IBSS. For WDS we add the sta for
 * the peer immediately upon device open. When using AP mode we add stations
 * for each respective station upon request from userspace through nl80211.
 *
 * In order to remove a STA info structure, various sta_info_destroy_*()
 * calls are available.
 *
 * There is no concept of ownership on a STA entry, each structure is
 * owned by the global hash table/list until it is removed. All users of
 * the structure need to be RCU protected so that the structure won't be
 * freed before they are done using it.
 */

/* Caller must hold local->sta_lock */
static int sta_info_hash_del(struct atbm_common *hw_priv,
			     struct sta_info *sta)
{
	struct sta_info *s;

	s = rcu_dereference_protected(hw_priv->sta_hash[STA_HASH(sta->sta.addr)],
				      lockdep_is_held(&hw_priv->sta_lock));
	if (!s)
		return -ENOENT;
	if (s == sta) {
		rcu_assign_pointer(hw_priv->sta_hash[STA_HASH(sta->sta.addr)],
				   s->hnext);
		return 0;
	}

	while (rcu_access_pointer(s->hnext) &&
	       rcu_access_pointer(s->hnext) != sta)
		s = rcu_dereference_protected(s->hnext,
					lockdep_is_held(&hw_priv->sta_lock));
	if (rcu_access_pointer(s->hnext)) {
		rcu_assign_pointer(s->hnext, sta->hnext);
		return 0;
	}

	return -ENOENT;
}

/* protected by RCU */
struct sta_info *sta_info_get(struct atbm_vif *priv,
			      const u8 *addr)
{
	struct atbm_common *hw_priv = priv->hw_priv;
	struct sta_info *sta;

	sta = rcu_dereference_check(hw_priv->sta_hash[STA_HASH(addr)],
				    lockdep_is_held(&hw_priv->sta_lock) ||
				    lockdep_is_held(&hw_priv->sta_mtx));
	while (sta) {
		if (sta->vif == priv &&
		    memcmp(sta->sta.addr, addr, ETH_ALEN) == 0)
			break;
		sta = rcu_dereference_check(sta->hnext,
					    lockdep_is_held(&hw_priv->sta_lock) ||
					    lockdep_is_held(&hw_priv->sta_mtx));
	}
	return sta;
}

/* get a station info entry even if it is a dummy station*/
struct sta_info *sta_info_get_rx(struct atbm_vif *priv,
			      const u8 *addr)
{
	struct atbm_common *hw_priv = priv->hw_priv;
	struct sta_info *sta;

	sta = rcu_dereference_check(hw_priv->sta_hash[STA_HASH(addr)],
				    lockdep_is_held(&hw_priv->sta_lock) ||
				    lockdep_is_held(&hw_priv->sta_mtx));
	while (sta) {
		if (sta->vif == priv &&
		    memcmp(sta->sta.addr, addr, ETH_ALEN) == 0)
			break;
		sta = rcu_dereference_check(sta->hnext,
					    lockdep_is_held(&hw_priv->sta_lock) ||
					    lockdep_is_held(&hw_priv->sta_mtx));
	}
	return sta;
}

/**
 * __sta_info_free - internal STA free helper
 *
 * @local: pointer to the global information
 * @sta: STA info to free
 *
 * This function must undo everything done by sta_info_alloc()
 * that may happen before sta_info_insert().
 */
static void __sta_info_free(struct atbm_common *hw_priv,
			    struct sta_info *sta)
{
	
	atbm_kfree(sta);
}

/* Caller must hold local->sta_lock */
static void sta_info_hash_add(struct atbm_common *hw_priv,
			      struct sta_info *sta)
{
	sta->hnext = hw_priv->sta_hash[STA_HASH(sta->sta.addr)];
	rcu_assign_pointer(hw_priv->sta_hash[STA_HASH(sta->sta.addr)], sta);
}
struct sta_info *sta_info_alloc(struct atbm_vif *priv,
				u8 *addr, gfp_t gfp)
{
	struct atbm_common *hw_priv = priv->hw_priv;
	struct sta_info *sta;
	int i;

	sta = atbm_kzalloc(sizeof(*sta), gfp);
	if (!sta)
		return NULL;

	spin_lock_init(&sta->lock);
	INIT_WORK(&sta->ampdu_mlme.work, ieee80211_ba_session_work);
	mutex_init(&sta->ampdu_mlme.mtx);

	memcpy(sta->sta.addr, addr, ETH_ALEN);
	sta->hw_priv = hw_priv;
	sta->vif = priv;

	for (i = 0; i < STA_TID_NUM; i++) {
		/*
		 * timer_to_tid must be initialized with identity mapping
		 * to enable session_timer's data differentiation. See
		 * sta_rx_agg_session_timer_expired for usage.
		 */
		sta->timer_to_tid[i] = i;
	}
	for (i = 0; i < NUM_RX_DATA_QUEUES; i++)
		sta->last_seq_ctrl[i] = cpu_to_le16(USHRT_MAX);
	
	return sta;
}

int sta_info_destroy_addr(struct atbm_vif *priv, const u8 *addr)
{
	struct atbm_common *hw_priv = priv->hw_priv;
	struct sta_info *sta;
	int ret;

	mutex_lock(&hw_priv->sta_mtx);
	sta = sta_info_get_rx(priv, addr);
	ret = __sta_info_destroy(sta);
	mutex_unlock(&hw_priv->sta_mtx);

	return ret;
}

static int sta_info_finish_insert(struct sta_info *sta,
				bool async, bool dummy_reinsert)
{
	struct atbm_common *hw_priv = sta->hw_priv;
	unsigned long flags;

	lockdep_assert_held(&hw_priv->sta_mtx);

	if (!sta->dummy || dummy_reinsert) {
		sta->uploaded = true;
	}

	if (!dummy_reinsert) {
		if (!async) {
			hw_priv->num_sta++;
			smp_mb();

			/* make the station visible */
			spin_lock_irqsave(&hw_priv->sta_lock, flags);
			sta_info_hash_add(hw_priv, sta);
			spin_unlock_irqrestore(&hw_priv->sta_lock, flags);
		}

		list_add(&sta->list, &hw_priv->sta_list);
	} else {
		sta->dummy = false;
	}
	return 0;
}

/*
 * should be called with sta_mtx locked
 * this function replaces the mutex lock
 * with a RCU lock
 */
static int sta_info_insert_non_ibss(struct sta_info *sta) __acquires(RCU)
{
	struct atbm_common *hw_priv  = sta->hw_priv;
	struct atbm_vif *priv = sta->vif;
	unsigned long flags;
	struct sta_info *exist_sta;
	bool dummy_reinsert = false;
	int err = 0;

	lockdep_assert_held(&hw_priv->sta_mtx);

	/*
	 * On first glance, this will look racy, because the code
	 * in this function, which inserts a station with sleeping,
	 * unlocks the sta_lock between checking existence in the
	 * hash table and inserting into it.
	 *
	 * However, it is not racy against itself because it keeps
	 * the mutex locked.
	 */

	spin_lock_irqsave(&hw_priv->sta_lock, flags);
	/*
	 * check if STA exists already.
	 * only accept a scenario of a second call to sta_info_insert_non_ibss
	 * with a dummy station entry that was inserted earlier
	 * in that case - assume that the dummy station flag should
	 * be removed.
	 */
	exist_sta = sta_info_get(priv, sta->sta.addr);
	if (exist_sta) {
		if (exist_sta == sta && sta->dummy) {
			dummy_reinsert = true;
		} else {
			spin_unlock_irqrestore(&hw_priv->sta_lock, flags);
			mutex_unlock(&hw_priv->sta_mtx);
			rcu_read_lock();
			return -EEXIST;
		}
	}

	spin_unlock_irqrestore(&hw_priv->sta_lock, flags);

	err = sta_info_finish_insert(sta, false, dummy_reinsert);
	if (err) {
		mutex_unlock(&hw_priv->sta_mtx);
		rcu_read_lock();
		return err;
	}


	/* move reference to rcu-protected */
	rcu_read_lock();
	mutex_unlock(&hw_priv->sta_mtx);
	return 0;
}

int sta_info_insert_rcu(struct sta_info *sta) __acquires(RCU)
{
	struct atbm_common *hw_priv  = sta->hw_priv;
	int err = 0;
	/*
	 * In ad-hoc mode, we sometimes need to insert stations
	 * from tasklet context from the RX path. To avoid races,
	 * always do so in that case -- see the comment below.
	 */
	/*
	 * It might seem that the function called below is in race against
	 * the function call above that atomically inserts the station... That,
	 * however, is not true because the above code can only
	 * be invoked for IBSS interfaces, and the below code will
	 * not be -- and the two do not race against each other as
	 * the hash table also keys off the interface.
	 */

	might_sleep();

	mutex_lock(&hw_priv->sta_mtx);

	err = sta_info_insert_non_ibss(sta);
	if (err)
		goto out_free;

	return 0;
 out_free:
	BUG_ON(!err);
	__sta_info_free(hw_priv, sta);
	return err;
}

int sta_info_insert(struct sta_info *sta)
{
	int err = sta_info_insert_rcu(sta);

	rcu_read_unlock();

	return err;
}

/* Caller must hold sta->local->sta_mtx */
int sta_info_reinsert(struct sta_info *sta)
{
	int err = 0;

	might_sleep();

	err = sta_info_insert_non_ibss(sta);
	rcu_read_unlock();
	return err;
}

int  __sta_info_destroy(struct sta_info *sta)
{
	struct atbm_common *hw_priv;
	struct atbm_vif *priv;
	unsigned long flags;
	int ret;

	might_sleep();

	if (!sta)
		return -ENOENT;

	hw_priv = sta->hw_priv;
	priv = sta->vif;

	/*
	 * Before removing the station from the driver and
	 * rate control, it might still start new aggregation
	 * sessions -- block that to make sure the tear-down
	 * will be sufficient.
	 */
	set_sta_flag(sta, WLAN_STA_BLOCK_BA);
	ieee80211_sta_tear_down_BA_sessions(sta, true);

	spin_lock_irqsave(&hw_priv->sta_lock, flags);
	ret = sta_info_hash_del(hw_priv, sta);
	/* this might still be the pending list ... which is fine */
	if (!ret)
		list_del(&sta->list);
	spin_unlock_irqrestore(&hw_priv->sta_lock, flags);
	if (ret)
		return ret;


	sta->dead = true;

	hw_priv->num_sta--;

	if (sta->uploaded) {
	}

	/*
	 * At this point, after we wait for an RCU grace period,
	 * neither mac80211 nor the driver can reference this
	 * sta struct any more except by still existing timers
	 * associated with this station that we clean up below.
	 */
	synchronize_rcu();
	__sta_info_free(hw_priv, sta);

	return 0;
}
void sta_info_init(struct atbm_common *hw_priv)
{
	spin_lock_init(&hw_priv->sta_lock);
	mutex_init(&hw_priv->sta_mtx);
	INIT_LIST_HEAD(&hw_priv->sta_list);
	INIT_LIST_HEAD(&hw_priv->sta_pending_list);
}

void sta_info_stop(struct atbm_common *hw_priv)
{
	sta_info_flush(hw_priv, NULL);
}

/**
 * sta_info_flush - flush matching STA entries from the STA table
 *
 * Returns the number of removed STA entries.
 *
 * @local: local interface data
 * @sdata: matching rule for the net device (sta->dev) or %NULL to match all STAs
 */
int sta_info_flush(struct atbm_common *hw_priv,
		  struct atbm_vif *priv)
{
	struct sta_info *sta, *tmp;
	int ret = 0;

	might_sleep();

	mutex_lock(&hw_priv->sta_mtx);

	list_for_each_entry_safe(sta, tmp, &hw_priv->sta_list, list) {
		if (!priv || priv == sta->vif)
			WARN_ON(__sta_info_destroy(sta));
	}
	mutex_unlock(&hw_priv->sta_mtx);

	return ret;
}
