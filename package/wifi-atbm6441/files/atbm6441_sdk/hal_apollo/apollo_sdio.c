/*
 * Mac80211 SDIO driver for altobeam APOLLO device
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on apollo code Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */
 #define DEBUG 1
//#undef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ 
#ifdef LINUX_OS
#include <linux/version.h>
#include <linux/module.h>
#include <linux/gpio.h>
#include <linux/delay.h>
#include <linux/mmc/host.h>
#include <linux/mmc/sdio_func.h>
#include <linux/mmc/card.h>
#include <linux/mmc/sdio.h>
#include <linux/spinlock.h>
#include <net/atbm_mac80211.h>
#include <linux/kthread.h>
#include <linux/notifier.h>
#include <linux/reboot.h>
#include <linux/platform_device.h>
#include <linux/sched.h>
#include <linux/freezer.h>
#include <linux/netdevice.h>
#include <linux/rtnetlink.h>
//#include "soc/mmc.h"
#endif



#include "apollo.h"
#include "sbus.h"
#include "apollo_plat.h"
#include "debug.h"
#include "hwio.h"
#include "svn_version.h"
#include "bh.h"
#include "module_fs.h"
#include "atbm_ioctl.h"
MODULE_DESCRIPTION("mac80211 altobeam apollo wifi SDIO driver");
MODULE_LICENSE("GPL");
MODULE_ALIAS("atbm_wlan");
struct build_info{
	int ver;
	int dpll;
	char driver_info[64];
};
extern int atbm_bh_read_ctrl_reg_unlock(struct atbm_common *hw_priv,
					  u16 *ctrl_reg);
static void atbm_sdio_release_err_cmd(struct atbm_common	*hw_priv);
static void atbm_sdio_lock(struct sbus_priv *self);
static void atbm_sdio_unlock(struct sbus_priv *self);

//const char DRIVER_INFO[]={"[====="__DATE__" "__TIME__"""=====]"};
const char DRIVER_INFO[]={"[==2022/9/26==="" """"=====]"};
static int driver_build_info(void)
{
	struct build_info build;
	build.ver=DRIVER_VER;
	if (DPLL_CLOCK==1)
		build.dpll=40;
	else if(DPLL_CLOCK==2)
		build.dpll=24;
	else
		build.dpll=26;
	memcpy(build.driver_info,(void*)DRIVER_INFO,sizeof(DRIVER_INFO));
	atbm_printk_always("SVN_VER=%d,DPLL_CLOCK=%d,BUILD_TIME=%s\n",build.ver,build.dpll,build.driver_info);


#if (PROJ_TYPE==HERA)
	atbm_printk_always("----drvier support chip HERA \n");
#endif

	return 0;
}
enum{
	THREAD_WAKEUP,
	THREAD_SHOULD_SUSPEND,
	THREAD_SUSPENED,
	THREAD_SHOULD_STOP,
};
struct atbm_sdio_thread
{
	const char *name;
	struct task_struct		__rcu *thread;
	unsigned long			flags;
	unsigned long           wakeup_period;
	struct completion 		suspended;
	int (*thread_fn)(void *priv);
	int (*period_handle)(struct atbm_sdio_thread *thread);
	int (*pre_sched)(struct atbm_sdio_thread *thread);
	int (*post_sched)(struct atbm_sdio_thread *thread);
	struct sbus_priv *self;
};
struct sbus_priv {
	struct sdio_func	*func;
	struct atbm_common	*core;
	struct atbm_sdio_thread tx_thread;
	struct atbm_sdio_thread rx_thread;
#ifndef LINUX_OS
	struct semaphore tx_wake;
	struct semaphore rx_wake;
	atomic_t tx_get;
	atomic_t rx_get;
#endif
	const struct atbm_platform_data *pdata;
	spinlock_t		lock;
	spinlock_t		bh_lock;
	sbus_irq_handler	irq_handler;
	sbus_irq_handler	irq_handler_suspend;
	int 			atbm_bgf_irq;
	int 			oob_irq_enabled;
	void			*irq_priv;
	void            *irq_priv_suspend;
	
	struct sbus_wtd         * wtd;
};
struct sbus_wtd {
	int 	wtd_init;
	struct task_struct		*wtd_thread;
	wait_queue_head_t		wtd_evt_wq;
	atomic_t				wtd_term;
	atomic_t				wtd_run;
	atomic_t				wtd_probe;
};
static const struct sdio_device_id atbm_sdio_ids[] = {
	{ SDIO_DEVICE(SDIO_ANY_ID, SDIO_ANY_ID) },
	{ /* end: all zeroes */			},
};

extern struct atbm_common *g_hw_priv;
extern int is_pre_rmmod;

static int  atbm_sdio_init(void);
static void  atbm_sdio_exit(void);
extern 	int atbm_plat_request_gpio_irq(const struct atbm_platform_data *pdata,struct sbus_priv *self,int * atbm_bgf_irq);
extern 	void atbm_plat_free_gpio_irq(const struct atbm_platform_data *pdata,struct sbus_priv *self,int atbm_bgf_irq);
static int atbm_sdio_reset_chip(struct sbus_priv *self);
extern void atbm_sdio_rx_bh(struct atbm_common *hw_priv);
extern void atbm_sdio_tx_bh(struct atbm_common *hw_priv);
extern int atbm_bh_read_ctrl_reg(struct atbm_common *hw_priv,
					  u16 *ctrl_reg);
static void atbm_sdio_miss_irq(struct sbus_priv *self);
#ifdef CONFIG_ATBM_SDIO_ATCMD
extern void atbm_sdio_tx_atcmd(struct atbm_common *hw_priv);
#endif

static struct sbus_wtd         g_wtd={
	.wtd_init  = 0,
	.wtd_thread = NULL,
};
#ifdef LINUX_OS
static struct task_struct *atbm_kthread_get(struct atbm_sdio_thread *thread)
{
	struct task_struct *bh = NULL;
	
	rcu_read_lock();
	bh = rcu_dereference(thread->thread);
	if(bh){
		get_task_struct(bh);
	}
	rcu_read_unlock();

	return bh;
}

static void atbm_kthread_put(struct task_struct *bh)
{
	put_task_struct(bh);
}
static int atbm_kthread_try_suspend(struct atbm_sdio_thread *thread)
{	
	struct task_struct *bh = atbm_kthread_get(thread);
	
	if(bh == NULL)
		goto exit;
	
	if(test_bit(THREAD_SHOULD_STOP,&thread->flags))
		goto exit;
	
	if (!test_bit(THREAD_SUSPENED, &thread->flags)) {
		
		set_bit(THREAD_SHOULD_SUSPEND, &thread->flags);
		
		if(bh != current){
			wake_up_process(bh);
			/*
			*set timeout is safe
			*/
			wait_for_completion_timeout(&thread->suspended,msecs_to_jiffies(1000));
		}
	}
exit:	
	if(bh)
		atbm_kthread_put(bh);
	return 0;
}
static void atbm_kthread_resume(struct atbm_sdio_thread *thread)
{
	struct task_struct *bh = atbm_kthread_get(thread);
	
	if(bh == NULL){
		return;
	}
	
	clear_bit(THREAD_SHOULD_SUSPEND, &thread->flags);
	if (test_and_clear_bit(THREAD_SUSPENED, &thread->flags)) {		
		wake_up_process(bh);
	}
	
	atbm_kthread_put(bh);
}

static int atbm_kthread_should_stop(struct atbm_sdio_thread *thread)
{
	if(!kthread_should_stop()){
		return 0;
	}
	set_bit(THREAD_SHOULD_STOP,&thread->flags);
	if(test_bit(THREAD_SHOULD_SUSPEND, &thread->flags)) {
		if (!test_and_set_bit(THREAD_SUSPENED, &thread->flags))
			complete(&thread->suspended);
	}

	return 1;
}

static void atbm_kthread_into_suspend(struct atbm_sdio_thread *thread)
{
	__set_current_state(TASK_INTERRUPTIBLE);
	while (test_bit(THREAD_SHOULD_SUSPEND, &thread->flags)) {
		if (!test_and_set_bit(THREAD_SUSPENED, &thread->flags))
			complete(&thread->suspended);	
		if(kthread_should_stop()){
			set_bit(THREAD_SHOULD_STOP,&thread->flags);
			clear_bit(THREAD_SHOULD_SUSPEND, &thread->flags);
			break;
		}else {
			schedule();
		}
		__set_current_state(TASK_INTERRUPTIBLE);
	}
	clear_bit(THREAD_SUSPENED, &thread->flags);
	__set_current_state(TASK_INTERRUPTIBLE);
}
#endif

static int atbm_sdio_wait_action(struct atbm_sdio_thread *thread)
{
	#ifdef LINUX_OS
	unsigned long idle_period = thread->wakeup_period;
	unsigned long period = idle_period;
wake:
	period = idle_period;
	set_current_state(TASK_INTERRUPTIBLE);	
	while (!atbm_kthread_should_stop(thread)) {
		if (test_and_clear_bit(THREAD_WAKEUP,
				       &thread->flags)) {
			if(thread->post_sched) thread->post_sched(thread);
			__set_current_state(TASK_RUNNING);
			return 0;
		}else if(test_bit(THREAD_SHOULD_SUSPEND,&thread->flags)){
			
			atbm_printk_pm("%s: go to suspend...\n",__func__);
			atbm_kthread_into_suspend(thread);
			atbm_printk_pm("%s: exit from suspend...\n",__func__);
			goto wake;
		}else if(period == 0){
			if(thread->period_handle && thread->period_handle(thread)){
				goto wake;
			}
		}
		if(thread->pre_sched && thread->pre_sched(thread)){
			goto wake;
		}
		set_current_state(TASK_INTERRUPTIBLE);
		if (!atbm_kthread_should_stop(thread))
			period = schedule_timeout(idle_period);
		set_current_state(TASK_INTERRUPTIBLE);
		
	}
	__set_current_state(TASK_RUNNING);
	return -1;
	#else
	return 0;
	#endif
}
static int atbm_sdio_irq_period(struct atbm_sdio_thread *thread)
{
	int ret = 0;
	u16 ctrl_reg = 0;
	struct sbus_priv *self = (struct sbus_priv *)thread->self;
	struct atbm_common *hw_priv = self->core;
	#ifdef LINUX_OS
	printk_once("[atbm_log]:rx timeout\n");
	
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	/*
	*check sdio irq thread has process the irq;
	*/
	if(test_bit(THREAD_WAKEUP,&thread->flags)){
		ret = 1;
		goto exit;
	}
	atbm_bh_read_ctrl_reg_unlock(hw_priv, &ctrl_reg);	
	if(ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_MASK){
		__set_current_state(TASK_RUNNING);
		atbm_printk_err("%s:Miss\n",__func__);
		atbm_sdio_miss_irq(hw_priv->sbus_priv);
		ret = 1;
		goto exit;
	}
exit:
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	#endif
	return ret;
}
static int atbm_sdio_rx_pre_sched(struct atbm_sdio_thread *thread)
{
	int ret = 0;
	u16 ctrl_reg = 0;
	struct sbus_priv *self = (struct sbus_priv *)thread->self;
	struct atbm_common *hw_priv = self->core;
	#ifdef LINUX_OS

	if (is_pre_rmmod && (hw_priv->wsm_caps.firmwareVersion>=13549)){
		return ret;
	}
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	atbm_bh_read_ctrl_reg_unlock(hw_priv, &ctrl_reg);
	
	if(ctrl_reg & ATBM_HIFREG_CONT_NEXT_LEN_MASK){
		__set_current_state(TASK_RUNNING);
		atbm_sdio_miss_irq(hw_priv->sbus_priv);
		ret = 1;
		goto exit;
	}
	
#ifdef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
	atbm_oob_intr_set(hw_priv->sbus_priv,true);
#endif		
	__atbm_irq_enable(hw_priv,1);
exit:
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	#endif
	return ret;
}
static int atbm_sdio_rx_post_sched(struct atbm_sdio_thread *thread)
{
	#ifdef LINUX_OS
	thread->pre_sched = atbm_sdio_rx_pre_sched;
	#endif
	return 0;
}

#ifndef LINUX_OS
extern int g_get_sdio_which_mci;
#endif

static int atbm_sdio_rx_thread(void *priv)
{
	struct sbus_priv *self = (struct sbus_priv *)priv;
	struct sched_param param = { .sched_priority = 1 };
	
	atbm_printk_init("%s\n",__func__);
	/*
	*the policy of the sheduler is same with the sdio irq thread
	*/
#if (LINUX_VERSION_CODE > KERNEL_VERSION(5, 9, 0))
		sched_set_fifo(current);
#else
		sched_setscheduler(current, SCHED_FIFO, &param);
#endif
	
	while(!atbm_sdio_wait_action(&self->rx_thread)){
		#ifndef LINUX_OS
		process_wait_timeout(&self->rx_wake, msecs_to_jiffies(10001));//too smaal will block tshell
		//if (!atomic_xchg(&self->rx_get, 0)){
		//	continue;
		//}
		if (self->core->init_done != 1){
			continue;
		}
		#endif
		atbm_sdio_rx_bh(self->core);
		#ifndef LINUX_OS
		clear_bit(THREAD_WAKEUP, &self->rx_thread.flags);
		atbm_sdio_lock(self);
		__atbm_irq_enable(self->core,1);
		atbm_sdio_unlock(self);
		sdio_enable_irq(g_get_sdio_which_mci, 1);
		#endif
	};
	atbm_printk_init("%s:exit\n",__func__);
	return 0;
}
static int atbm_sdio_tx_period(struct atbm_sdio_thread *thread)
{
	return 1;
}
static int atbm_sdio_tx_thread(void *priv)
{
	struct sbus_priv *self = (struct sbus_priv *)priv;
#ifdef CONFIG_ATBM_SDIO_SMP
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 9, 0))
	struct sched_param param = { .sched_priority = 1 };
#endif 
#else
#if (LINUX_VERSION_CODE < KERNEL_VERSION(5, 9, 0))
	struct sched_param param = { .sched_priority = 2 };
#endif
#endif

	atbm_printk_init("%s\n",__func__);
#if (LINUX_VERSION_CODE > KERNEL_VERSION(5, 9, 0))
	sched_set_fifo(current);
#else
	sched_setscheduler(current, SCHED_FIFO, &param);
#endif		
	while(!atbm_sdio_wait_action(&self->tx_thread)){
		#ifndef LINUX_OS
		process_wait_timeout(&self->tx_wake, HZ);
		//if (!atomic_xchg(&self->tx_get, 0)){
		//	continue;
		//}
		#endif
#ifdef CONFIG_ATBM_SDIO_TX_HOLD	
		atbm_sdio_lock(self);
#endif
		atbm_sdio_tx_bh(self->core);
		#ifndef LINUX_OS
		clear_bit(THREAD_WAKEUP, &self->tx_thread.flags);
		#endif
#ifdef CONFIG_ATBM_SDIO_TX_HOLD	
		atbm_sdio_unlock(self);
#endif
	}
	atbm_printk_init("%s:exit\n",__func__);
	atbm_sdio_release_err_cmd(self->core);
	return 0;
}
static int atbm_sdio_thread_init(struct atbm_sdio_thread *thread)
{
	void *bh;
	struct sbus_priv *self = thread->self;
	
	bh = kthread_create(thread->thread_fn,self, thread->name);
	if (IS_ERR(bh)){
		thread->thread = NULL;
		atbm_printk_err("sdio %s err\n",thread->name);
		return -1;
	}else {
		spin_lock_bh(&self->bh_lock);
		rcu_assign_pointer(thread->thread,bh);
		spin_unlock_bh(&self->bh_lock);
		init_completion(&thread->suspended);
	}

	return 0;
}

#ifdef LINUX_OS
static struct rcu_synchronize_atbm {
	struct rcu_head head;
	struct completion completion;
}atbm_rcu;

//static struct rcu_synchronize_atbm atbm_rcu;

static void wakeme_after_rcu_atbm(struct rcu_head *head)
{
	struct rcu_synchronize_atbm *rcu;

	rcu = container_of(head, struct rcu_synchronize_atbm, head);
	complete(&rcu->completion);
}

static void asynchronize_rcu(void)
{
	static int init_cnt = 0;

	if (init_cnt){
		init_rcu_head_on_stack(&atbm_rcu.head);
		init_completion(&atbm_rcu.completion);
		call_rcu(&atbm_rcu.head, wakeme_after_rcu_atbm);
	}
	init_cnt++;
}
#endif

static int atbm_sdio_thread_deinit(struct atbm_sdio_thread *thread)
{
	void *bh;
	struct sbus_priv *self = thread->self;

	set_bit(THREAD_SHOULD_STOP,&thread->flags);
	spin_lock_bh(&self->bh_lock);
	bh = rcu_dereference(thread->thread);
	rcu_assign_pointer(thread->thread,NULL);
	spin_unlock_bh(&self->bh_lock);
	if (bh){
		asynchronize_rcu();
		kthread_stop(bh);
	}

	return 0;
}

static int atbm_sdio_thread_wakeup(struct atbm_sdio_thread *thread)
{
	void *bh;
	
	rcu_read_lock();
	if(test_and_set_bit(THREAD_WAKEUP, &thread->flags) == 0){
		bh = rcu_dereference(thread->thread);
		if(bh)
			wake_up_process((struct task_struct *)bh);
	}
	rcu_read_unlock();
	return 0;
}
static int atbm_sdio_xmit_init(struct sbus_priv *self)
{
	struct atbm_common *hw_priv = self->core;	
	struct atbm_sdio_thread *thread = &self->tx_thread;

	#ifndef LINUX_OS
	sema_init(&self->tx_wake, 0);
	atomic_set(&self->tx_get, 0);
	#endif

	thread->flags = 0;
	thread->name  = "sdio_tx";
	thread->pre_sched = NULL;
	thread->period_handle = atbm_sdio_tx_period;
	thread->thread_fn = atbm_sdio_tx_thread;
	thread->post_sched = NULL;
	thread->pre_sched = NULL;
	thread->self = self;
	thread->wakeup_period = msecs_to_jiffies(1000);

	if(atbm_sdio_thread_init(thread)){
		#ifndef LINUX_OS
		sema_destroy(&self->tx_wake);
		#endif
		return -1;
	}
	
	hw_priv->xmit_buff = atbm_kzalloc(SDIO_TX_MAXLEN, GFP_KERNEL);

	if(hw_priv->xmit_buff == NULL){
		return -1;
	}

	#ifndef LINUX_OS
	thread->thread->sem_task = &self->tx_wake;
	#endif
	return 0;
}

static int atbm_sdio_xmit_deinit(struct sbus_priv *self)
{
	atbm_printk_exit("atbm_sdio_xmit_deinit\n");

	atbm_sdio_thread_deinit(&self->tx_thread);
	
	if(self->core->xmit_buff){
		atbm_kfree(self->core->xmit_buff);
		self->core->xmit_buff = NULL;
	}	
	return 0;
}
static int atbm_sdio_rev_init(struct sbus_priv *self)
{
	struct atbm_sdio_thread *thread = &self->rx_thread;

	#ifndef LINUX_OS
	sema_init(&self->rx_wake, 0);
	atomic_set(&self->rx_get, 0);
	#endif

	thread->flags = 0;
	thread->name  = "sdio_rx";
	thread->period_handle = atbm_sdio_irq_period;
	thread->thread_fn = atbm_sdio_rx_thread;
	thread->post_sched = atbm_sdio_rx_post_sched;
	thread->wakeup_period = msecs_to_jiffies(30);
	thread->pre_sched  = NULL;
	thread->self = self;
	if(atbm_sdio_thread_init(thread)){
		#ifndef LINUX_OS
		sema_destroy(&self->rx_wake);
		#endif
		return -1;
	}
	#ifndef LINUX_OS
	thread->thread->sem_task = &self->rx_wake;
	#endif
	wake_up_process(thread->thread);
    return 0;
}

static int atbm_sdio_rev_deinit(struct sbus_priv *self)
{
	atbm_printk_exit("atbm_sdio_rev_deinit\n");
	
	return atbm_sdio_thread_deinit(&self->rx_thread);
}

static int atbm_sdio_xmit_schedule(struct sbus_priv *self)
{
	#ifndef LINUX_OS
	atomic_set(&self->tx_get, 1);
	#endif
	return atbm_sdio_thread_wakeup(&self->tx_thread);

}
static int atbm_sdio_rev_schedule(struct sbus_priv *self)
{
	#ifndef LINUX_OS
	atomic_set(&self->rx_get, 1);
	#endif
	return atbm_sdio_thread_wakeup(&self->rx_thread);
}
static int atbm_sdio_bh_suspend(struct sbus_priv *self)
{
	int ret = 0;
	#ifdef LINUX_OS
	ret = atbm_kthread_try_suspend(&self->tx_thread);
	ret |= atbm_kthread_try_suspend(&self->rx_thread);
	#endif
	return ret;
}
static int atbm_sdio_bh_resume(struct sbus_priv *self)
{
	int ret = 0;
	#ifdef LINUX_OS
	atbm_kthread_resume(&self->tx_thread);
	atbm_kthread_resume(&self->rx_thread);
	#endif
	return ret;
}
#if 0
static int atbm_sdio_rev_giveback(struct sbus_priv *self,void *giveback)
{
	struct atbm_common *hw_priv = self->core;
	struct wsm_rx *rx = (struct wsm_rx *)giveback;
	u32 hw_xmited = rx->channel_type;
	int hw_free;
	
	spin_lock_bh(&hw_priv->tx_com_lock);
	BUG_ON((int)hw_xmited > (int)hw_priv->n_xmits);
	if(hw_priv->n_xmits - hw_xmited <= hw_priv->wsm_caps.numInpChBufs){
		hw_free =  (hw_priv->wsm_caps.numInpChBufs-hw_priv->hw_bufs_used) - (hw_priv->n_xmits-hw_xmited);
		if(hw_priv->hw_bufs_free < hw_free)
			hw_priv->hw_bufs_free = hw_free;
	}
	spin_unlock_bh(&hw_priv->tx_com_lock);

	return 0;
}
#endif
/* sbus_ops implemetation */

static int atbm_sdio_memcpy_fromio(struct sbus_priv *self,
				     unsigned int addr,
				     void *dst, int count)
{
	if(is_pre_rmmod && (self->core->wsm_caps.firmwareVersion>=13549)){
		return -1;
	}
	return sdio_memcpy_fromio(self->func, dst, addr, count);
}

static int atbm_sdio_memcpy_toio(struct sbus_priv *self,
				   unsigned int addr,
				   const void *src, int count)
{
	if(is_pre_rmmod && (self->core->wsm_caps.firmwareVersion>=13549)){
		return -1;
	}
	return sdio_memcpy_toio(self->func, addr, (void *)src, count);
}

int atbm_sdio_memcpy_fromio_for_sleep(struct sbus_priv *self,
				     unsigned int addr,
				     void *dst, int count)
{
	return sdio_memcpy_fromio(self->func, dst, addr, count);
}

int atbm_sdio_memcpy_toio_for_sleep(struct sbus_priv *self,
				   unsigned int addr,
				   const void *src, int count)
{
	return sdio_memcpy_toio(self->func, addr, (void *)src, count);
}

static void atbm_sdio_lock(struct sbus_priv *self)
{
	sdio_claim_host(self->func);
}

static void atbm_sdio_unlock(struct sbus_priv *self)
{
	sdio_release_host(self->func);
}
#ifndef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
static void atbm_sdio_irq_handler(struct sdio_func *func)
{
	struct sbus_priv *self = atbm_sdio_get_drvdata(func);

	BUG_ON(!self);

	if (is_pre_rmmod && (self->core->wsm_caps.firmwareVersion>=13549)){
		return ;
	}
	if (self->irq_handler)
		self->irq_handler(self->irq_priv);
}
#endif
#ifdef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ

irqreturn_t atbm_gpio_hardirq(int irq, void *dev_id)
{
	return IRQ_WAKE_THREAD;
}
void atbm_oob_intr_set(struct sbus_priv *self, bool enable)
{
	unsigned long flags;

	if (!self)
		return;

	spin_lock_irqsave(&self->lock, flags);
	if (self->oob_irq_enabled != enable) {
		if (enable)
			enable_irq(self->atbm_bgf_irq);
		else
			disable_irq_nosync(self->atbm_bgf_irq);
		self->oob_irq_enabled = enable;
	}
	spin_unlock_irqrestore(&self->lock, flags);
}

irqreturn_t atbm_gpio_irq(int irq, void *dev_id)
{
	struct sbus_priv *self = dev_id;

	if (self) {
		bool sdio_hold = false;
		if(!in_interrupt()){
			sdio_hold = true;
			atbm_sdio_lock(self);
		}		
		atbm_oob_intr_set(self, 0);
		self->irq_handler(self->irq_priv);		
		if(sdio_hold == true){
			WARN_ON(in_interrupt());
			sdio_hold = false;
			atbm_sdio_unlock(self);
		}
		return IRQ_HANDLED;
	} else {
		return IRQ_NONE;
	}
}

unsigned int atbm_gpio_irq_hera(void *arg)
{
	struct sbus_priv *self = (struct sbus_priv *)arg;

	if (self->irq_handler)
		self->irq_handler(self->irq_priv);
}

static int atbm_request_irq(struct sbus_priv *self)
{
	int ret = 0;
	int func_num;
	u8 cccr;
//	int bgf_irq;
	
	/* Hack to access Fuction-0 */
	func_num = self->func->num;
	self->func->num = 0;

	cccr = sdio_readb(self->func, SDIO_CCCR_IENx, &ret);
	if (WARN_ON(ret))
		goto err;

	/* Master interrupt enable ... */
	cccr |= BIT(0);

	/* ... for our function */
	cccr |= BIT(func_num);

	sdio_writeb(self->func, cccr, SDIO_CCCR_IENx, &ret);
	if (WARN_ON(ret))
		goto err;

	/* back to	Fuction-1 */
	self->func->num = func_num;

	ret = atbm_plat_request_gpio_irq(self->pdata,self,&self->atbm_bgf_irq);
	//printk("========================bgf_irq=%d\n",bgf_irq);

	if (WARN_ON(ret))
		goto err;
	self->oob_irq_enabled = 1;

	return 0;

err:
	atbm_plat_free_gpio_irq(self->pdata,self,self->atbm_bgf_irq);
	atbm_printk_bus("[%s]  fail exiting sw_gpio_irq_request..   :%d\n",__func__, ret);
	return ret;
}
#endif
static void atbm_sdio_miss_irq(struct sbus_priv *self) 
{
#ifdef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
	atbm_oob_intr_set(self, 0);
#endif
	if (self->irq_handler)
		self->irq_handler(self->irq_priv);
}
static int atbm_sdio_irq_subscribe(struct sbus_priv *self,
				     sbus_irq_handler handler,
				     void *priv)
{
	int ret;
	unsigned long flags;

	if (!handler)
		return -EINVAL;

	spin_lock_irqsave(&self->lock, flags);
	self->irq_priv = priv;
	self->irq_handler = handler;
	spin_unlock_irqrestore(&self->lock, flags);

	atbm_printk_bus("[ATBM_WIFI]SW IRQ subscribe\n");
	sdio_claim_host(self->func);
#ifndef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
	#pragma message("atbm wifi SDIO_IRQ")
	atbm_printk_bus("[ATBM_WIFI] used SDIO Irq \n");
	ret = sdio_claim_irq(self->func, atbm_sdio_irq_handler);
	if (ret)
		atbm_printk_err("Failed to claim sdio Irq :%d\n",ret);
#else
	#pragma message("atbm wifi GPIO_IRQ")
	atbm_printk_bus("[ATBM_WIFI] used GPIO Irq \n");
	ret = atbm_request_irq(self);
#endif
	sdio_release_host(self->func);
	return ret;
}

static int atbm_sdio_irq_unsubscribe(struct sbus_priv *self)
{
	int ret = 0;
	unsigned long flags;
	//const struct resource *irq = self->pdata->irq;

	WARN_ON(!self->irq_handler);
	if (!self->irq_handler)
		return 0;

	atbm_printk_bus("[ATBM_WIFI]:SW IRQ unsubscribe\n");

#ifndef CONFIG_ATBM_APOLLO_USE_GPIO_IRQ
	sdio_claim_host(self->func);
	ret = sdio_release_irq(self->func);
	sdio_release_host(self->func);
#else
    atbm_plat_free_gpio_irq(self->pdata,self,self->atbm_bgf_irq);
	//free_irq(self->atbm_bgf_irq,self);
	//gpio_free(self->pdata->irq_gpio);
#endif  //CONFIG_ATBM_APOLLO_USE_GPIO_IRQ

	spin_lock_irqsave(&self->lock, flags);
	self->irq_priv = NULL;
	self->irq_handler = NULL;
	spin_unlock_irqrestore(&self->lock, flags);

	return ret;
}


#if ((ATBM_WIFI_PLATFORM != PLATFORM_ANKAI_RTOS) && (ATBM_WIFI_PLATFORM != 10) && (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_S805) \
	&& (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_905))
static int atbm_detect_card(const struct atbm_platform_data *pdata)
{
	/* HACK!!!
	 * Rely on mmc->class_dev.class set in mmc_alloc_host
	 * Tricky part: a new mmc hook is being (temporary) created
	 * to discover mmc_host class.
	 * Do you know more elegant way how to enumerate mmc_hosts?
	 */

	struct mmc_host *mmc = NULL;
	struct class_dev_iter iter;
	struct device *dev;
	static struct platform_device *sdio_platform_dev = NULL;
	int status = 0;
	
	sdio_platform_dev = platform_device_alloc("atbmsdiowifi",0);
	if(sdio_platform_dev == NULL){
		status = -ENOMEM;
		goto platform_dev_err;
	}

	if(platform_device_add(sdio_platform_dev) != 0){
		status = -ENOMEM;
		goto platform_dev_err;
	}
	
	mmc = mmc_alloc_host(0, &sdio_platform_dev->dev);
	
	if (!mmc){
		status = -ENOMEM;
		goto exit;
	}

	BUG_ON(!mmc->class_dev.class);
	class_dev_iter_init(&iter, mmc->class_dev.class, NULL, NULL);
	for (;;) {
		dev = class_dev_iter_next(&iter);
		if (!dev) {
			atbm_printk_err( "atbm: %s is not found.\n",
				pdata->mmc_id);
			break;
		} else {
			struct mmc_host *host = container_of(dev,
				struct mmc_host, class_dev);

			atbm_printk_bus("apollo:  found. %s\n",
				dev_name(&host->class_dev));

			if (dev_name(&host->class_dev) &&
				strcmp(dev_name(&host->class_dev),
					pdata->mmc_id))
				continue;

			if(host->card == NULL)
			{
				#if (ATBM_WIFI_PLATFORM == PLATFORM_INGENIC_T31)
			 	    extern int jzmmc_manual_detect(int index, int on);
					jzmmc_manual_detect(1,1);
				#else
					printk("mmc detect change\n");
					mmc_detect_change(host, 10);
				#endif
		    }
			else
				atbm_printk_err("%s has been attached\n",pdata->mmc_id);
			break;
		}
	}
	mmc_free_host(mmc);
exit:
	if(sdio_platform_dev)
		platform_device_unregister(sdio_platform_dev);
	return status;
platform_dev_err:
	if(sdio_platform_dev)
		platform_device_put(sdio_platform_dev);
	return status;
}
#endif //PLATFORM_AMLOGIC_S805

static int atbm_sdio_off(const struct atbm_platform_data *pdata)
{
	int ret = 0;

	if (pdata->insert_ctrl)
		ret = pdata->insert_ctrl(pdata, false);
	return ret;
}
#if ((ATBM_WIFI_PLATFORM != PLATFORM_ANKAI_RTOS) && (ATBM_WIFI_PLATFORM != 10) && (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_S805) \
	&& (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_905))

static int atbm_sdio_on(const struct atbm_platform_data *pdata)
{
	int ret = 0;
    if (pdata->insert_ctrl)
		ret = pdata->insert_ctrl(pdata, true);
#if (ATBM_WIFI_PLATFORM != PLATFORM_XM)
	msleep(200);
//	atbm_detect_card(pdata);
#endif
	return ret;
}
#endif //#if ((ATBM_WIFI_PLATFORM != 10) && (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_S805))

static int atbm_cmd52_abort(struct sbus_priv *self)
{
	int ret;
	int regdata;
	sdio_claim_host(self->func);

	/* SDIO Simplified Specification V2.0, 4.4 Reset for SDIO */
	regdata = sdio_f0_readb(self->func, SDIO_CCCR_ABORT, &ret);
	atbm_printk_err("%s,%d ret %d\n",__func__,__LINE__,ret);
	if (ret)
		regdata = 0x08;
	else
		regdata |= 0x01;
	sdio_f0_writeb(self->func, regdata, SDIO_CCCR_ABORT, &ret);
//	msleep(1500);
	atbm_printk_err("%s,%d ret %d\n",__func__,__LINE__,ret);
	sdio_release_host(self->func);
	return ret;
}

static int atbm_sdio_reset(struct sbus_priv *self)
{
	int ret;
	int regdata;
	int func_num;

	return 0;
	atbm_printk_bus("atbm_sdio_reset++\n");
	sdio_claim_host(self->func);
	/* Hack to access Fuction-0 */
	func_num = self->func->num;

	self->func->num = 0;

	/**********************/
	atbm_printk_bus("SDIO_RESET++\n");
	/* SDIO Simplified Specification V2.0, 4.4 Reset for SDIO */
	regdata = sdio_readb(self->func, SDIO_CCCR_ABORT, &ret);
	if (ret)
		regdata = 0x08;
	else
		regdata |= 0x08;
	sdio_writeb(self->func, regdata, SDIO_CCCR_ABORT, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;
	msleep(1500);
	regdata = sdio_readb(self->func, SDIO_CCCR_ABORT, &ret);
	atbm_printk_bus("SDIO_RESET-- 0x%x\n",regdata);

	/**********************/
	atbm_printk_bus("SDIO_SPEED_EHS++\n");
	regdata = sdio_readb(self->func, SDIO_CCCR_SPEED, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;

	regdata |= SDIO_SPEED_EHS;
	sdio_writeb(self->func, regdata, SDIO_CCCR_SPEED, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;

	regdata = sdio_readb(self->func, SDIO_CCCR_SPEED, &ret);
	atbm_printk_bus("SDIO_SPEED_EHS -- 0x%x:0x%x\n",regdata,SDIO_SPEED_EHS);

	/**********************/
	atbm_printk_bus("SDIO_BUS_WIDTH_4BIT++\n");
	regdata = sdio_readb(self->func, SDIO_CCCR_IF, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;

	//regdata |= SDIO_BUS_WIDTH_4BIT;
	regdata = 0xff;
	sdio_writeb(self->func, regdata, SDIO_CCCR_IF, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;
	regdata = sdio_readb(self->func, SDIO_CCCR_IF, &ret);
	atbm_printk_bus("SDIO_BUS_WIDTH_4BIT -- 0x%x:0x%x\n",regdata,SDIO_BUS_WIDTH_4BIT);
	/**********************/
	atbm_printk_bus("SDIO_BUS_ENABLE_FUNC++\n");
	regdata = sdio_readb(self->func, SDIO_CCCR_IOEx, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;
	regdata |= BIT(func_num);
	atbm_printk_bus("SDIO_BUS_ENABLE_FUNC regdata %x\n",regdata);
	sdio_writeb(self->func, regdata, SDIO_CCCR_IOEx, &ret);
	if (WARN_ON(ret))
		goto set_func0_err;
	regdata = sdio_readb(self->func, SDIO_CCCR_IOEx, &ret);
	atbm_printk_bus("SDIO_BUS_ENABLE_FUNC -- 0x%x\n",regdata);
	/**********************/

set_func0_err:
	self->func->num = func_num;
	sdio_set_block_size_(self->func,512);
	/* Restore the WLAN function number */
	sdio_release_host(self->func);

	return 0;
}

static u32 atbm_sdio_align_size(struct sbus_priv *self, u32 size)
{
	u32 aligned = sdio_align_size(self->func, size);
	return aligned;
}

int atbm_sdio_set_block_size(struct sbus_priv *self, u32 size)
{
	return sdio_set_block_size_(self->func, size);
}

static int atbm_sdio_pm(struct sbus_priv *self, bool  suspend)
{
	int ret = 0;
	return ret;
}
int atbm_wtd_term(struct atbm_common *hw_priv)
{
	return atomic_read(&hw_priv->sbus_priv->wtd->wtd_term);
}
void atbm_wtd_wakeup( struct sbus_priv *self)
{
#ifdef CONFIG_ATBMWIFI_WDT
	if(atomic_read(&self->wtd->wtd_term))
		return;
	atomic_set(&g_wtd.wtd_run, 1);
	atbm_printk_err("[atbm_wtd] wakeup.\n");
	wake_up(&self->wtd->wtd_evt_wq);
#endif //CONFIG_ATBMWIFI_WDT
}

static void atbm_wtd_init(void)
{
}
static void atbm_wtd_exit(void)
{
}
int atbm_reset_lmc_cpu(struct atbm_common *hw_priv)
{
	return 0;
}
static void atbm_sdio_release_err_cmd(struct atbm_common	*hw_priv)
{
	spin_lock_bh(&hw_priv->wsm_cmd.lock);
	if(hw_priv->wsm_cmd.cmd != 0XFFFF){
		hw_priv->wsm_cmd.ret = -1;
		hw_priv->wsm_cmd.done = 1;
		hw_priv->wsm_cmd.cmd = 0xFFFF;
		hw_priv->wsm_cmd.ptr = NULL;
		hw_priv->wsm_cmd.arg = NULL;
		printk_once(KERN_ERR "%s:release wsm_cmd.lock\n",__func__);		
		wake_up(&hw_priv->wsm_cmd_wq);		
	}	
	spin_unlock_bh(&hw_priv->wsm_cmd.lock);
}

static int __atbm_sdio_lmac_restart(struct sbus_priv *self)
{
	return -1;
}
static int atbm_sdio_lmac_restart(struct sbus_priv *self)
{
	int ret = -1;
	#ifdef LINUX_OS
	/*
	*it's safe to try device lock here when rmmod is running
	*here should not use device_lock,if so lock may be dead.
	*/
	if(device_trylock(&self->func->dev)){
		get_device(&self->func->dev);
		ret = __atbm_sdio_lmac_restart(self);
		put_device(&self->func->dev);
		device_unlock(&self->func->dev);
	}else {
		atbm_printk_err("%s:maybe sdio is disconneting\n",__func__);
	}
	#endif
	return ret;
}

static struct sbus_ops atbm_sdio_sbus_ops = {
	.sbus_memcpy_fromio	= atbm_sdio_memcpy_fromio,
	.sbus_memcpy_toio	= atbm_sdio_memcpy_toio,
	.sbus_read_sync 	= atbm_sdio_memcpy_fromio,
	.sbus_write_sync	= atbm_sdio_memcpy_toio,
	.lock				= atbm_sdio_lock,
	.unlock				= atbm_sdio_unlock,
	.irq_subscribe		= atbm_sdio_irq_subscribe,
	.irq_unsubscribe	= atbm_sdio_irq_unsubscribe,
	.reset				= atbm_sdio_reset,
	.align_size			= atbm_sdio_align_size,
	.power_mgmt			= atbm_sdio_pm,
	.set_block_size		= atbm_sdio_set_block_size,
	.wtd_wakeup			= atbm_wtd_wakeup,
	.sbus_reset_chip    = NULL, /* atbm_sdio_reset_chip - disabled to prevent infinite loop */
	.abort				= atbm_cmd52_abort,
	.lmac_restart   	= atbm_sdio_lmac_restart,
	//.sbus_cmd52_fromio =atbm_cmd52_fromio,
	//.sbus_cmd52_toio =atbm_cmd52_toio,
	.sbus_xmit_func_init   = atbm_sdio_xmit_init,
	.sbus_xmit_func_deinit  = atbm_sdio_xmit_deinit,
	.sbus_rev_func_init    = atbm_sdio_rev_init,
	.sbus_rev_func_deinit  = atbm_sdio_rev_deinit,
	.sbus_xmit_schedule    = atbm_sdio_xmit_schedule,
	.sbus_rev_schedule     = atbm_sdio_rev_schedule,
	.sbus_bh_suspend       = atbm_sdio_bh_suspend,
	.sbus_bh_resume        = atbm_sdio_bh_resume,
#if 0
	.sbus_rev_giveback	   = atbm_sdio_rev_giveback,
#endif
};

#ifdef TIME_DEBUG
static unsigned long jiffies_set[JIFFIES_INIT_MAX_CNT+JIFFIES_EXIT_MAX_CNT];
static unsigned long jiffies_index = 0;
static char *jiffies_init_name[JIFFIES_INIT_MAX_CNT]={
	"start",      "sdiostart",
	"register",   "probecall",
	"mainprobe",  "tx_rx",
	"load_fw",    "wait",
	"ready",      "net_add",
	"config",     "over"
};
static char *jiffies_exit_name[JIFFIES_EXIT_MAX_CNT]={
	"start",      "unregister",
	"disconn",    "rm_net",
	"un_irq",     "clos_txrx",
	"buf_clos",   "regchange",
	"dis_over",   "sdio_off",
	"others",     "over"
};
void jiffies_update(int is_first)
{
	if (is_first)
	{
		jiffies_index = 0;
	}
	jiffies_set[jiffies_index++] = jiffies;
}
static void jiffies_print(char *jiffies_name[], int is_init)
{
	int i = 0;
	int cnt = 0;

	if (is_init) {
		cnt = JIFFIES_INIT_MAX_CNT;
	}
	else {
		cnt = JIFFIES_EXIT_MAX_CNT;
	}

	for (i=0; i<cnt; i++) {
		printk("%10.10s", jiffies_name[i]);
	}
	printk("\n");
	for (i=0; i<cnt; i++) {
		printk("%10d", jiffies_to_msecs(jiffies_set[i]-jiffies_set[0]));
	}
	printk("\n");
}
#endif


/* Probe Function to be called by SDIO stack when device is discovered */
static int atbm_sdio_probe(struct sdio_func *func,
			      const struct sdio_device_id *id)
{
	struct sbus_priv *self;
	int status;

	atbm_dbg(ATBM_APOLLO_DBG_INIT, "Probe called\n");
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	atomic_set(&g_wtd.wtd_probe, 0);
	#ifdef LINUX_OS
	func->card->quirks|=MMC_QUIRK_LENIENT_FN0;
	func->card->quirks |= MMC_QUIRK_BLKSZ_FOR_BYTE_MODE;
	#endif
	self = atbm_kzalloc(sizeof(*self), GFP_KERNEL);
	if (!self) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR, "Can't allocate SDIO sbus_priv.");
		return -ENOMEM;
	}

	spin_lock_init(&self->lock);
	spin_lock_init(&self->bh_lock);
	self->pdata = atbm_get_platform_data();
	self->func = func;
	self->wtd = &g_wtd;
	atbm_sdio_set_drvdata(func, self);
	sdio_claim_host(func);
	atbm_sdio_enable_func(func);
	sdio_release_host(func);

	//reset test start
	//atbm_sdio_reset(self);
	//reset test end

	atbm_printk_init("%s:v12\n",__func__);
	status = atbm_core_probe(&atbm_sdio_sbus_ops,
			      self, &func->dev, &self->core);
	if (status) {
		sdio_claim_host(func);
		atbm_sdio_disable_func(func);
		sdio_release_host(func);
		atbm_sdio_set_drvdata(func, NULL);
		atbm_kfree(self);
		atomic_set(&g_wtd.wtd_probe, -1);
		//printk("[atbm_wtd]:set wtd_probe = -1\n");
	}
	else {
		atomic_set(&g_wtd.wtd_probe, 1);
		atbm_printk_exit("[atbm_wtd]:set wtd_probe = 1\n");
		#ifdef TIME_DEBUG
		jiffies_update(0);
		jiffies_print(jiffies_init_name, 1);
		#endif
	}
	return status;
}

/* Disconnect Function to be called by SDIO stack when
 * device is disconnected */
static int atbm_sdio_reset_chip(struct sbus_priv *self)
{
	atbm_printk_bus("%s\n",__func__);
	atbm_reset_lmc_cpu(self->core);
	return 0;
}
static void atbm_sdio_disconnect(struct sdio_func *func)
{
	struct sbus_priv *self = atbm_sdio_get_drvdata(func);
	atbm_printk_exit("atbm_sdio_disconnect");
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	if (self) {
		atomic_set(&g_wtd.wtd_probe, 0);
		
		if (self->core) {
			atbm_core_release(self->core);
#if (ATBM_WIFI_PLATFORM != PLATFORM_XM)
			self->core = NULL;
#endif
		}

		sdio_claim_host(func);
		atbm_sdio_disable_func(func);
		sdio_release_host(func);
		atbm_sdio_set_drvdata(func, NULL);
#if (ATBM_WIFI_PLATFORM == PLATFORM_XM)
		atbm_sdio_irq_unsubscribe(self->core->sbus_priv);
		self->core = NULL;
#endif
		atbm_kfree(self);
		#ifdef TIME_DEBUG
		jiffies_update(0);
		#endif
	}
}

static int atbm_suspend(struct device *dev)
{
	int ret;
	#ifdef LINUX_OS
	struct sdio_func *func = dev_to_sdio_func(dev);
	struct sbus_priv *self = atbm_sdio_get_drvdata(func);
	/* Notify SDIO that CW1200 will remain powered during suspend */
	mmc_pm_flag_t flags=sdio_get_host_pm_caps(func);
	//printk("mmc_pm_flag=%x\n",flags);
	if(!(flags&MMC_PM_KEEP_POWER)){
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"cant remain alive while host is suspended\n");
		return -ENOSYS;
	}
	ret = sdio_set_host_pm_flags(func, MMC_PM_KEEP_POWER);
	if (ret)
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			   "set sdio keep pwr flag failed:%d\n", ret);
	/*sdio irq wakes up host*/
	if (flags&MMC_PM_WAKE_SDIO_IRQ){
		ret = sdio_set_host_pm_flags(func, MMC_PM_WAKE_SDIO_IRQ);
	}
	if (ret)
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			   "set sdio wake up irq flag failed:%d\n", ret);
	atbm_printk_err("sdio suspend\n");	
	ret = atbm_bh_suspend(self->core);
	if(ret == 0){
		self->irq_handler_suspend = self->irq_handler;
		self->irq_priv_suspend    = self->irq_priv;
		atbm_sdio_irq_unsubscribe(self);
	}
	#endif
	return ret;
}

static int atbm_resume(struct device *dev)
{
	#ifdef LINUX_OS
	struct sdio_func *func = dev_to_sdio_func(dev);
	struct sbus_priv *self = atbm_sdio_get_drvdata(func);
	int ret = 0;
	
	atbm_printk_err("sdio resume\n");
	atbm_sdio_lock(self);
	atbm_printk_err("%s:disable irq\n",__func__);
	__atbm_irq_enable(self->core,0);
	atbm_sdio_unlock(self);
	if(self->irq_handler_suspend && self->irq_priv_suspend){
		atbm_sdio_irq_subscribe(self,self->irq_handler_suspend,self->irq_priv_suspend);
		self->irq_handler_suspend = NULL;
		self->irq_priv_suspend = NULL;
	}
	atbm_sdio_lock(self);
	atbm_printk_err("%s:enable irq\n",__func__);
	__atbm_irq_enable(self->core,1);
	atbm_sdio_unlock(self);
	ret = atbm_bh_resume(self->core);
	#endif
	return 0;
}

static const struct dev_pm_ops atbm_pm_ops = {
	.suspend = atbm_suspend,
	.resume = atbm_resume,
};

static struct sdio_driver sdio_driver = {
	.name		= "atbm_wlan",
	.id_table	= atbm_sdio_ids,
	.probe		= atbm_sdio_probe,
	.remove		= atbm_sdio_disconnect,
	.drv = {
		.pm = &atbm_pm_ops,
	}
};
static int atbm_reboot_notifier(struct notifier_block *nb,
				unsigned long action, void *unused)
{
	atbm_printk_exit("atbm_reboot_notifier\n");
	atomic_set(&g_wtd.wtd_term, 1);
	atomic_set(&g_wtd.wtd_run, 0);
	/* The MCU sends HI_SDIO_StartUp_Indication only once, at its own boot,
	 * so a host-only reboot always leaves the next probe without a WSM
	 * startup indication (stale session -> wsm_seq mismatch, HIF HW ERR).
	 * On restart the MCU must reboot with us: WSM_FORCE_REBOOT (0x003C)
	 * cold-starts the MCU (which also resets the SoC on this board).
	 * On halt/poweroff keep the stock notify+fw_sleep battery behavior. */
	if (g_hw_priv && g_hw_priv->wsm_caps.firmwareVersion) {
		if (action == SYS_RESTART) {
			atbm_wsm_force_reboot(g_hw_priv);
		} else {
			atbm_wsm_host_reboot_notify(g_hw_priv);
			if (g_hw_priv->wsm_caps.firmwareVersion >= 13549)
				atbm_wsm_fw_sleep(g_hw_priv);
		}
	}
	atbm_sdio_exit();
	//atbm_ieee80211_exit();
	atbm_release_firmware();
	return NOTIFY_DONE;
}

/* Probe Function to be called by USB stack when device is discovered */
static struct notifier_block atbm_reboot_nb = {
	.notifier_call = atbm_reboot_notifier,
	.priority=1,
};

extern int atbm_detect_func_enable(void);

int has_func_enable = 0;

/* Init Module function -> Called by insmod */
static int  atbm_sdio_init(void)
{
	const struct atbm_platform_data *pdata;
	int ret;
	pdata = atbm_get_platform_data();

	ret=driver_build_info();
	if (pdata->clk_ctrl) {
		ret = pdata->clk_ctrl(pdata, true);
		if (ret)
			goto err_clk;
	}
/*
* modify for rockchip platform
*/
#if (ATBM_WIFI_PLATFORM == 10)
	if (pdata->insert_ctrl&&pdata->power_ctrl)
	{
		ret = pdata->insert_ctrl(pdata, false);
		ret = pdata->power_ctrl(pdata, false);
		if (ret)
			goto err_power;
		ret = pdata->power_ctrl(pdata, true);
		if (ret)
			goto err_power;
		ret = pdata->insert_ctrl(pdata, true);
	}
	else
	{
		goto err_power;
	}
#else
	if (pdata->power_ctrl) {
		ret = pdata->power_ctrl(pdata, true);
		if (ret)
			goto err_power;
	}
#endif
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif

	ret = atbm_detect_func_enable();
	if (ret == 1)
	{
		printk("[FUNC_ENABLE] has been set to 1 --->\n");
		has_func_enable = 1;
	}

	ret = atbm_sdio_register_driver(&sdio_driver);
	if (ret)
		goto err_reg;
#if ((ATBM_WIFI_PLATFORM != PLATFORM_ANKAI_RTOS) && (ATBM_WIFI_PLATFORM != 10) && (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_S805)\
	&& (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_905))
	if (!has_func_enable)
	{
		ret = atbm_sdio_on(pdata);
		if (ret)
			goto err_on;
	}
#endif
	atbm_wtd_init();
	return 0;

#if ((ATBM_WIFI_PLATFORM != 10) && (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_S805)\
	&& (ATBM_WIFI_PLATFORM != PLATFORM_AMLOGIC_905))

err_on:
	if (pdata->power_ctrl)
		pdata->power_ctrl(pdata, false);
#endif
err_power:
	if (pdata->clk_ctrl)
		pdata->clk_ctrl(pdata, false);
err_clk:
	atbm_sdio_unregister_driver(&sdio_driver);
err_reg:
	return ret;
}

/* Called at Driver Unloading */
static void  atbm_sdio_exit(void)
{
	const struct atbm_platform_data *pdata;
	pdata = atbm_get_platform_data();
	atbm_wtd_exit();
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	atbm_sdio_unregister_driver(&sdio_driver);
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	atbm_sdio_off(pdata);
	if (pdata->power_ctrl)
		pdata->power_ctrl(pdata, false);
	if (pdata->clk_ctrl)
		pdata->clk_ctrl(pdata, false);
}

#ifdef LINUX_OS
static 
#endif
int __init apollo_sdio_module_init(void)
{
	printk("\nDRIVER VER: %s.\n", PRIV_VERSION);
	#ifdef TIME_DEBUG
	jiffies_update(1);
	#endif
	#ifdef LINUX_OS
	atbm_ioctl_add();
	#endif
	ieee80211_atbm_mem_int();
	ieee80211_atbm_skb_int();
	atbm_module_attribute_init();
	register_reboot_notifier(&atbm_reboot_nb);
	atbm_init_firmware();
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	return atbm_sdio_init();
}

#ifdef LINUX_OS
static 
#endif
void  apollo_sdio_module_exit(void)
{	
	#ifdef TIME_DEBUG
	jiffies_update(1);
	#endif
	atomic_set(&g_wtd.wtd_term, 1);
	atomic_set(&g_wtd.wtd_run, 0);
	atbm_sdio_exit();
	#ifdef TIME_DEBUG
	jiffies_update(0);
	#endif
	atbm_release_firmware();
	unregister_reboot_notifier(&atbm_reboot_nb);
	atbm_module_attribute_exit();
	ieee80211_atbm_mem_exit();
	ieee80211_atbm_skb_exit();
	#ifdef LINUX_OS
	atbm_ioctl_free();
	/* wait rcu sync complete */
	wait_for_completion(&atbm_rcu.completion);
	destroy_rcu_head_on_stack(&atbm_rcu.head);
	#endif
	#ifdef TIME_DEBUG
	jiffies_update(0);
	jiffies_print(jiffies_exit_name, 0);
	#endif
}


module_init(apollo_sdio_module_init);
module_exit(apollo_sdio_module_exit);
