/*
 * Mac80211 power management interface for altobeam APOLLO mac80211 drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on apollo code
 * Copyright (c) 2011, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef PM_H_INCLUDED
#define PM_H_INCLUDED

#ifdef CONFIG_WAKELOCK
#include <linux/wakelock.h>
#endif

/* ******************************************************************** */
/* mac80211 API								*/

#ifdef CONFIG_PM

/* extern */  struct atbm_common;
/* private */ struct atbm_suspend_state;
struct atbm_pm_stayawake_lock{
	int stayawak_cnt;
	spinlock_t stayawak_spinlock;
	#ifdef CONFIG_WAKELOCK
	struct wake_lock stayawak_lock;
	#endif
};
struct atbm_pm_state {
#ifdef CONFIG_WAKELOCK
	struct wake_lock wakelock;
#else
	struct atbm_timer_list stay_awake;
#endif
	struct platform_device *pm_dev;
	spinlock_t lock;
	struct atbm_pm_stayawake_lock stayawake_lock;
	int b_init;
};

struct atbm_pm_state_vif {
	struct atbm_suspend_state *suspend_state;
};

int atbm_pm_init(struct atbm_pm_state *pm,
		    struct atbm_common *priv);
void atbm_pm_deinit(struct atbm_pm_state *pm);
void atbm_pm_stay_awake(struct atbm_pm_state *pm,
			  unsigned long tmo);
void atbm_pm_stay_awake_lock(struct atbm_pm_state *pm);
void atbm_pm_stay_awake_unlock(struct atbm_pm_state *pm);
#endif
#endif
