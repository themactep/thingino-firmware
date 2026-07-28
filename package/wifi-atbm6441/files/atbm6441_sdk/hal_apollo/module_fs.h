#ifndef __MODULE_FS_H__
#define __MODULE_FS_H__
#ifdef LINUX_OS
#include <linux/hash.h>
#endif
#include "ieee80211_i.h"
extern int atbm_module_attribute_init(void);
extern void atbm_module_attribute_exit(void);
struct ieee80211_internal_mac{
	u8 mac[6];
	struct hlist_node hnode;
};

#endif
