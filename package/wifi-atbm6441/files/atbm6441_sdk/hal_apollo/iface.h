/*
 * O(1) TX queue with built-in allocator for altobeam APOLLO drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on apollo code
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifndef ATBM_IFACE_H_INCLUDED
#define ATBM_IFACE_H_INCLUDED
#ifdef LINUX_OS
#include <linux/kernel.h>
#include <linux/device.h>
#include <linux/if_ether.h>
#include <linux/interrupt.h>
#include <linux/list.h>
#include <linux/hash.h>
#include <linux/netdevice.h>
#include <linux/skbuff.h>
#include <linux/workqueue.h>
#include <linux/types.h>
#include <linux/spinlock.h>
#include <linux/etherdevice.h>
#include <linux/leds.h>
#include <net/ieee80211_radiotap.h>
#include <net/cfg80211.h>
#include <net/atbm_mac80211.h>
#endif
#include "apollo.h"
static inline struct atbm_vif *
atbm_dev_to_vif(struct net_device *dev)
{
	return netdev_priv(dev);
}
/* Required encryption head and tailroom */
#define IEEE80211_ENCRYPT_HEADROOM 20
#define IEEE80211_ENCRYPT_TAILROOM 18

#ifndef CONFIG_ATBM_SDIO_ATCMD
int atbm_netdev_add(struct atbm_common *hw_priv,const char *name);
#else
int atbm_netdev_none(struct atbm_common *hw_priv);
#endif

void atbm_remove_interfaces(struct atbm_common *hw_priv);
void ieee80211_send_auth(struct        atbm_vif *vif,
			 u16 transaction, u16 auth_alg,
			 u8 *extra, size_t extra_len, const u8 *bssid,
			 const u8 *key, u8 key_len, u8 key_idx);
void atbm_sta_disconnect_event(struct atbm_vif *vif,u8 *bssid);
void atbm_sta_connect_event(struct atbm_vif *vif,struct HostConnectEvent * hostevent);
void atbm_sta_add_event(struct atbm_vif *vif, int link_id);
void atbm_sta_loss_event(struct atbm_vif *vif);

#endif /* ATBM_APOLLO_QUEUE_H_INCLUDED */
