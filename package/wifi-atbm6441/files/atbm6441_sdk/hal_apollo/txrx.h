/*
 * Datapath interface for altobeam APOLLO mac80211 drivers
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

#ifndef ATBM_APOLLO_TXRX_H
#define ATBM_APOLLO_TXRX_H

#ifdef LINUX_OS
#include <linux/list.h>
#endif

/* extern */ struct sk_buff;
/* extern */ struct wsm_tx;
/* extern */ struct wsm_rx;
/* extern */ struct wsm_tx_confirm;
/* extern */ struct atbm_vif;
/* ******************************************************************** */
/* TX implementation							*/
/* ******************************************************************** */
/* WSM callbacks							*/

/* ******************************************************************** */
/* Timeout								*/
/* ******************************************************************** */
/* Security								*/
void atbm_tx(struct atbm_vif *vif, struct sk_buff *skb);

#if 0
/* ******************************************************************** */
/* Workaround for WFD test case 6.1.10					*/
void atbm_link_id_reset(struct work_struct *work);
#endif
#endif /* ATBM_APOLLO_TXRX_H */
