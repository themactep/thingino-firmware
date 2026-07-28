/*
 *  HT-related code for altobeam APOLLO driver
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

#ifndef ATBM_APOLLO_HT_H_INCLUDED
#define ATBM_APOLLO_HT_H_INCLUDED

#include <net/atbm_mac80211.h>

struct atbm_ht_info {
	struct ieee80211_sta_ht_cap	ht_cap;
	enum nl80211_channel_type	channel_type;
	u16				operation_mode;
};

static inline int atbm_is_ht(const struct atbm_ht_info *ht_info)
{
	return ht_info->channel_type != NL80211_CHAN_NO_HT;
}

static inline int atbm_ht_greenfield(const struct atbm_ht_info *ht_info)
{
	return atbm_is_ht(ht_info) &&
		(ht_info->ht_cap.cap & IEEE80211_HT_CAP_GRN_FLD) &&
		!(ht_info->operation_mode &
			IEEE80211_HT_OP_MODE_NON_GF_STA_PRSNT);
}

static inline int atbm_ht_ampdu_density(const struct atbm_ht_info *ht_info)
{
	if (!atbm_is_ht(ht_info))
		return 0;
	return ht_info->ht_cap.ampdu_density;
}

#endif /* ATBM_APOLLO_HT_H_INCLUDED */
