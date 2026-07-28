/*
 * Mac80211 power management API for altobeam APOLLO drivers
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

#ifdef LINUX_OS
#include <linux/platform_device.h>
#include <linux/if_ether.h>
#endif
#include "apollo.h"
#include "pm.h"
#include "bh.h"
#include "sbus.h"

#define ATBM_APOLLO_BEACON_SKIPPING_MULTIPLIER 3

static int atbm_suspend_late(struct device *dev);
#if 0
static void atbm_pm_release(struct device *dev);
#endif
static int atbm_pm_probe(struct platform_device *pdev);

/* private */
struct atbm_suspend_state {
	unsigned long bss_loss_tmo;
	unsigned long connection_loss_tmo;
	unsigned long join_tmo;
	unsigned long direct_probe;
	unsigned long link_id_gc;
	bool beacon_skipping;
};

static const struct dev_pm_ops atbm_pm_ops = {
	.suspend_noirq = atbm_suspend_late,
};

static struct platform_driver atbm_power_driver = {
	.probe = atbm_pm_probe,
	.driver = {
		.name = "atbm_power",
		.pm = &atbm_pm_ops,
	},
};

static int atbm_pm_init_common(struct atbm_pm_state *pm,
				  struct atbm_common *hw_priv)
{
	int ret;

	spin_lock_init(&pm->lock);
	ret = platform_driver_register(&atbm_power_driver);
	if (ret)
		return ret;
	pm->pm_dev = platform_device_alloc("atbm_power", 0);
	if (!pm->pm_dev) {
		platform_driver_unregister(&atbm_power_driver);
		return -ENOMEM;
	}

	pm->pm_dev->dev.platform_data = hw_priv;
	ret = platform_device_add(pm->pm_dev);
	if (ret) {
		atbm_kfree(pm->pm_dev);
		pm->pm_dev = NULL;
	}

	return ret;
}
static int atbm_pm_init_stayawake_lock(struct atbm_pm_stayawake_lock *stayawake_lock)
{
	unsigned long flags;
	spin_lock_init(&stayawake_lock->stayawak_spinlock);
	#ifdef CONFIG_PM
	#ifdef CONFIG_WAKELOCK
	wake_lock_init(&stayawake_lock->stayawak_lock,WAKE_LOCK_SUSPEND, "atbm_wlan_stayawake");
	#endif
	#endif
	spin_lock_irqsave(&stayawake_lock->stayawak_spinlock,flags);
	stayawake_lock->stayawak_cnt = 0;
	spin_unlock_irqrestore(&stayawake_lock->stayawak_spinlock,flags);
	
	return 0;
}
static int atbm_pm_deinit_stayawake_lock(struct atbm_pm_stayawake_lock *stayawake_lock)
{
	#ifdef CONFIG_PM
	#ifdef CONFIG_WAKELOCK
	unsigned long flags;
	spin_lock_irqsave(&stayawake_lock->stayawak_spinlock,flags);
	if (wake_lock_active(&stayawake_lock->stayawak_lock))
		wake_unlock(&stayawake_lock->stayawak_lock);
	stayawake_lock->stayawak_cnt = 0;
	spin_unlock_irqrestore(&stayawake_lock->stayawak_spinlock,flags);
	wake_lock_destroy(&stayawake_lock->stayawak_lock);
	#endif
	#endif
	
	return 0;
}
static void atbm_pm_deinit_common(struct atbm_pm_state *pm)
{
	platform_driver_unregister(&atbm_power_driver);
	if (pm->pm_dev) {
		pm->pm_dev->dev.platform_data = NULL;
		platform_device_unregister(pm->pm_dev);
		pm->pm_dev = NULL;
	}
}
#ifdef CONFIG_PM
#ifdef CONFIG_WAKELOCK

int atbm_pm_init(struct atbm_pm_state *pm,
		   struct atbm_common *hw_priv)
{
	int ret = atbm_pm_init_common(pm, hw_priv);
	if (!ret){
		wake_lock_init(&pm->wakelock,
			WAKE_LOCK_SUSPEND, "atbm_wlan");
		atbm_pm_init_stayawake_lock(&pm->stayawake_lock);
		smp_mb();
		pm->b_init = 1;
	}
	return ret;
}

void atbm_pm_deinit(struct atbm_pm_state *pm)
{
	if(pm->b_init==0)
		return ;
	pm->b_init =0;
	smp_mb();
	if (wake_lock_active(&pm->wakelock))
		wake_unlock(&pm->wakelock);
	wake_lock_destroy(&pm->wakelock);
	atbm_pm_deinit_common(pm);
	atbm_pm_deinit_stayawake_lock(&pm->stayawake_lock);
}

void atbm_pm_stay_awake(struct atbm_pm_state *pm,
			  unsigned long tmo)
{
	long cur_tmo;
	
	if(pm->b_init==0)
		return ;
	spin_lock_bh(&pm->lock);
#if (LINUX_VERSION_CODE >=KERNEL_VERSION(3,4,0))
	cur_tmo = pm->wakelock.ws.timer_expires - jiffies;
#else
 	cur_tmo = pm->wakelock.expires - jiffies;
#endif
	if (!wake_lock_active(&pm->wakelock) ||
			cur_tmo < (long)tmo)
		wake_lock_timeout(&pm->wakelock, tmo);
	spin_unlock_bh(&pm->lock);
}

#else /* CONFIG_WAKELOCK */

static void atbm_pm_stay_awake_tmo(unsigned long arg)
{
}

int atbm_pm_init(struct atbm_pm_state *pm,
		   struct atbm_common *hw_priv)
{
	int ret = atbm_pm_init_common(pm, hw_priv);
	if (!ret) {
		atbm_init_timer(&pm->stay_awake);
		pm->stay_awake.data = (unsigned long)pm;
		pm->stay_awake.function = atbm_pm_stay_awake_tmo;
		atbm_pm_init_stayawake_lock(&pm->stayawake_lock);
	}
	return ret;
}

void atbm_pm_deinit(struct atbm_pm_state *pm)
{
	atbm_del_timer_sync(&pm->stay_awake);
	atbm_pm_deinit_common(pm);
	atbm_pm_deinit_stayawake_lock(&pm->stayawake_lock);
}

void atbm_pm_stay_awake(struct atbm_pm_state *pm,
			  unsigned long tmo)
{
	long cur_tmo;
	spin_lock_bh(&pm->lock);
	cur_tmo = pm->stay_awake.expires - jiffies;
	if (!atbm_timer_pending(&pm->stay_awake) ||
			cur_tmo < (long)tmo)
		atbm_mod_timer(&pm->stay_awake, jiffies + tmo);
	spin_unlock_bh(&pm->lock);
}

#endif /* CONFIG_WAKELOCK */

void atbm_pm_stay_awake_lock(struct atbm_pm_state *pm)
{
	#ifdef CONFIG_WAKELOCK
	unsigned long flags;
	struct atbm_pm_stayawake_lock *stayawake_lock = &pm->stayawake_lock;
	if(pm->b_init==0)
		return ;
	spin_lock_irqsave(&stayawake_lock->stayawak_spinlock,flags);
	if(stayawake_lock->stayawak_cnt++ == 0){
		wake_lock(&stayawake_lock->stayawak_lock);
	}
	spin_unlock_irqrestore(&stayawake_lock->stayawak_spinlock,flags);
	#else
	pm = pm;
	#endif
}

void atbm_pm_stay_awake_unlock(struct atbm_pm_state *pm)
{
	#ifdef CONFIG_WAKELOCK
	unsigned long flags;
	struct atbm_pm_stayawake_lock *stayawake_lock = &pm->stayawake_lock;
	if(pm->b_init==0)
		return ;

	spin_lock_irqsave(&stayawake_lock->stayawak_spinlock,flags);
	BUG_ON(stayawake_lock->stayawak_cnt == 0);
	if(--stayawake_lock->stayawak_cnt == 0){
		wake_unlock(&stayawake_lock->stayawak_lock);
	}
	spin_unlock_irqrestore(&stayawake_lock->stayawak_spinlock,flags);
	//bm_pm_stay_awake(pm,HZ);
	#else
	pm = pm;
	#endif
}

#endif

static int atbm_suspend_late(struct device *dev)
{
	return 0;
}

static int atbm_pm_probe(struct platform_device *pdev)
{
	return 0;
}

