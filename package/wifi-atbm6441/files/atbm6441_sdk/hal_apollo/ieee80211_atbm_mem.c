/*
 * Datapath implementation for altobeam APOLLO mac80211 drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 *Based on apollo code
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#include <net/atbm_mac80211.h>
#include <linux/etherdevice.h>
#include <linux/skbuff.h>
#include <net/ip.h>
#include <linux/kobject.h>
#include <linux/module.h>
#include "ieee80211_i.h"

#if defined (ATBM_ALLOC_MEM_DEBUG)
#pragma message("Mem Debug Enable")
#define ATBM_MEM_SHOW_BUFF_MAX_SIZE		PAGE_SIZE
#define ATBM_MEM_SHOW_PUT(_show,...)	\
	do{										\
		int ret = 0;						\
		ret = scnprintf((_show)->show_buff+(_show)->show_count,(_show)->show_size-(_show)->show_count,__VA_ARGS__);		\
		if(ret>=0)	(_show)->show_count+=ret;				\
	}while(0)
#define ATBM_MEM_RESERV			(64-((sizeof(char *)+sizeof(struct list_head))%64))
struct ieee80211_atbm_mem
{
	struct list_head head;
	const char *call_addr;
	u32 mem_len;
	u8 mem[0] __attribute__((__aligned__(64)));
};

struct ieee80211_atbm_mem_show
{
	char *show_buff;
	int  show_count;
	int  show_size;
};
static struct list_head ieee80211_atbm_mem_list;
static spinlock_t ieee80211_atbm_mem_spin_lock;
static struct kobject *atbm_mem_kobj = NULL;
static u32 mem_add_generation = 0;
static u32 mem_del_generation = 0;

static ssize_t atbm_mem_show(struct kobject *kobj,struct kobj_attribute *attr, char *buf);

static struct kobj_attribute atbm_mem_attr = __ATTR(atbmmem, 0444, atbm_mem_show, NULL);

static struct attribute *atbm_mem_attribute_group[]= {
	&atbm_mem_attr.attr,
	NULL,
};

static struct attribute_group atbm_mem_attr_group = {
	.attrs = atbm_mem_attribute_group,
};
static void *__ieee80211_atbm_kmalloc(size_t s, gfp_t gfp,const char *call_addr)
{
	struct ieee80211_atbm_mem *atbm_mem = NULL;
	void *p = NULL;
	unsigned long flags;
	
	atbm_mem = kmalloc(s+sizeof(struct ieee80211_atbm_mem),gfp);
	atbm_printk_debug( "alloc atbm_mem(%p)\n",atbm_mem);
	if(atbm_mem){
		p = (void*)atbm_mem->mem;
		atbm_mem->call_addr = call_addr;
		atbm_mem->mem_len = s+sizeof(struct ieee80211_atbm_mem);
		spin_lock_irqsave(&ieee80211_atbm_mem_spin_lock, flags);
		list_add_tail(&atbm_mem->head, &ieee80211_atbm_mem_list);
		mem_add_generation++;
		spin_unlock_irqrestore(&ieee80211_atbm_mem_spin_lock, flags);
	}

	return p;
}
void *ieee80211_atbm_kmalloc(size_t s, gfp_t gfp,const char *func)
{
	void *p = __ieee80211_atbm_kmalloc(s, gfp,func);
	return p;
}

//void *ieee80211_atbm_kzalloc(size_t s, gfp_t gfp,void* call_addr)
void *ieee80211_atbm_kzalloc(size_t s, gfp_t gfp,const char *func)
{
	void *p = __ieee80211_atbm_kmalloc(s, gfp,func);
	if(p)
		memset(p, 0, s);
	return p;
}
void *ieee80211_atbm_kcalloc(size_t n, size_t size, gfp_t gfp,const char *func)
{
	if((n == 0) || (size==0))
		return NULL;
	return ieee80211_atbm_kzalloc(n*size, gfp | __GFP_ZERO,func);
}

void *ieee80211_atbm_krealloc(void *p, size_t new_size, gfp_t gfp,const char *func)
{
	struct ieee80211_atbm_mem *atbm_mem = NULL;
	struct ieee80211_atbm_mem *atbm_mem_new = NULL;
	void *p_new = NULL;
	unsigned long flags;
	
	if((p == NULL)||(new_size == 0))
		return NULL;

	atbm_mem = container_of(p, struct ieee80211_atbm_mem, mem);

	
	spin_lock_irqsave(&ieee80211_atbm_mem_spin_lock, flags);	
	list_del(&atbm_mem->head);
	mem_del_generation++;
	spin_unlock_irqrestore(&ieee80211_atbm_mem_spin_lock, flags);

	atbm_mem_new = krealloc(atbm_mem,new_size+sizeof(struct ieee80211_atbm_mem),gfp);

	if(atbm_mem_new){
		p_new = (void*)atbm_mem_new->mem;
		atbm_mem_new->call_addr = func;
		atbm_mem_new->mem_len = new_size+sizeof(struct ieee80211_atbm_mem);
		spin_lock_irqsave(&ieee80211_atbm_mem_spin_lock, flags);		
		list_add_tail(&atbm_mem_new->head, &ieee80211_atbm_mem_list);
		mem_add_generation++;
		spin_unlock_irqrestore(&ieee80211_atbm_mem_spin_lock, flags);
	}

	return p_new;
}

void ieee80211_atbm_kfree(void *p)
{
	struct ieee80211_atbm_mem *atbm_mem = NULL;
	unsigned long flags;
	
	if(p == NULL)
		return;
	atbm_mem = container_of(p, struct ieee80211_atbm_mem, mem);

	spin_lock_irqsave(&ieee80211_atbm_mem_spin_lock, flags);	
	list_del(&atbm_mem->head);
	mem_del_generation++;
	spin_unlock_irqrestore(&ieee80211_atbm_mem_spin_lock, flags);

	kfree(atbm_mem);
}
static ssize_t atbm_mem_show(struct kobject *kobj,
			     struct kobj_attribute *attr, char *buf)
{
	struct ieee80211_atbm_mem_show mem_show;
	unsigned long flags;
	struct ieee80211_atbm_mem *atbm_mem = NULL;
	u32 mem_in_list = 0;
	u32 mem_total_bytes = 0;
	
	mem_show.show_buff = buf;
	mem_show.show_count = 0;
	mem_show.show_size = ATBM_MEM_SHOW_BUFF_MAX_SIZE;

	spin_lock_irqsave(&ieee80211_atbm_mem_spin_lock, flags);
	ATBM_MEM_SHOW_PUT(&mem_show,"mem_lis:add[%d],del[%d],left[%d]\n",
		mem_add_generation,mem_del_generation,mem_add_generation - mem_del_generation);
	list_for_each_entry(atbm_mem, &ieee80211_atbm_mem_list, head) {
		ATBM_MEM_SHOW_PUT(&mem_show,"[%s][%p]\n", atbm_mem->call_addr,atbm_mem);
		mem_in_list++;
		mem_total_bytes += atbm_mem->mem_len;
	}
	ATBM_MEM_SHOW_PUT(&mem_show,"mem in use[%d],total bytes[%d],true byes[%d]\n",
		mem_in_list,mem_total_bytes,(u32)(mem_total_bytes-sizeof(struct ieee80211_atbm_mem)*mem_in_list));
	spin_unlock_irqrestore(&ieee80211_atbm_mem_spin_lock, flags);

	return mem_show.show_count;
}
static int ieee80211_atbm_mem_object_int(void)
{
	int error;

	atbm_mem_kobj = kobject_create_and_add("atbm_mem",
					    atbm_module_parent);
	if (!atbm_mem_kobj)
		return -EINVAL;

	error = sysfs_create_group(atbm_mem_kobj, &atbm_mem_attr_group);
	if (error)
		kobject_put(atbm_mem_kobj);
	return error;
}
static void ieee80211_atbm_mem_object_exit(void)
{
	if(atbm_mem_kobj == NULL)
		return;
	sysfs_remove_group(atbm_mem_kobj, &atbm_mem_attr_group);
	kobject_put(atbm_mem_kobj);
}
void ieee80211_atbm_mem_exit(void)
{
	struct ieee80211_atbm_mem *atbm_mem = NULL;
	unsigned long flags;
	atbm_printk_exit("ieee80211_atbm_mem_exit\n");
	spin_lock_irqsave(&ieee80211_atbm_mem_spin_lock, flags);
	while (!list_empty(&ieee80211_atbm_mem_list)) {
		atbm_mem = list_first_entry(
			&ieee80211_atbm_mem_list, struct ieee80211_atbm_mem, head);

		atbm_printk_always("%s:malloc addr(%s)\n",__func__,atbm_mem->call_addr);
		list_del(&atbm_mem->head);
		kfree(atbm_mem);
	}
	spin_unlock_irqrestore(&ieee80211_atbm_mem_spin_lock, flags);
	ieee80211_atbm_mem_object_exit();
}

void ieee80211_atbm_mem_int(void)
{
	atbm_printk_init("%s:%d\n",__func__,(u32)sizeof(struct ieee80211_atbm_mem));
	spin_lock_init(&ieee80211_atbm_mem_spin_lock);
	INIT_LIST_HEAD(&ieee80211_atbm_mem_list);
	ieee80211_atbm_mem_object_int();
}
#endif
