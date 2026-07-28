/*
 * DebugFS code for altobeam APOLLO mac80211 driver
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

#ifndef ATBM_APOLLO_DEBUG_H_INCLUDED
#define ATBM_APOLLO_DEBUG_H_INCLUDED


struct cw200_common;


#define ATBM_APOLLO_DBG_MSG		0x00000001
#define ATBM_APOLLO_DBG_NIY		0x00000002
#define ATBM_APOLLO_DBG_SBUS		0x00000004
#define ATBM_APOLLO_DBG_INIT		0x00000008
#define ATBM_APOLLO_DBG_ERROR	0x00000010
#define ATBM_APOLLO_DBG_DCXO_DPLL  0x00000020
#define ATBM_APOLLO_DBG_LEVEL	(ATBM_APOLLO_DBG_INIT|ATBM_APOLLO_DBG_NIY|ATBM_APOLLO_DBG_ERROR)


#define FUNC_ENTER() //printk("%s %d++\n",__func__,__LINE__)
#define FUNC_EXIT() //printk("%s %d--\n",__func__,__LINE__)


#define atbm_dbg(level, ...)				\
 if ((level) & ATBM_APOLLO_DBG_LEVEL)		\
		atbm_printk_init(__VA_ARGS__);	\

extern u32 atbm_control_debug_mask;

#define ATBM_CONTROL_DEBUG_RX     BIT(0)
#define ATBM_CONTROL_DEBUG_TX     BIT(1)
#define ATBM_CONTROL_DEBUG_SLEEP  BIT(2)

#define atbm_control_dbg(level, ...)				\
  if ((level) & atbm_control_debug_mask)		 \
		 atbm_printk_init(__VA_ARGS__);  \

 /* TODO It should be removed before official delivery */
 static __inline void frame_hexdump(char *prefix, u8 *data, int len)
 {
	 int i;

	atbm_printk_always("%s hexdump:\n", prefix);
	 for (i = 0; i < len; i++) {
	 	if((i % 16)==0)
			printk(KERN_ERR "\n");
		printk(KERN_ERR "%02x ", data[i]);

	 }
	printk(KERN_ERR "\n");
 }
void ATBMWIFI_DBG_PRINT2(const char * func,const int line,unsigned int data);
void ATBMWIFI_DBG_PRINT(const char * func,const int line);

struct atbm_debug_param{
	void *private;
	char *buff;
	int size;
	int cout;
};
/*
*atbm printk
*/
#define atbm_printk_err(...) 		atbm_printk(ATBM_PRINTK_MASK_ERR,__VA_ARGS__)
#define atbm_printk_warn(...)		atbm_printk(ATBM_PRINTK_MASK_WARN,__VA_ARGS__)
#define atbm_printk_init(...)		atbm_printk(ATBM_PRINTK_MASK_INIT,__VA_ARGS__)
#define atbm_printk_exit(...)		atbm_printk(ATBM_PRINTK_MASK_EXIT,__VA_ARGS__)
#define atbm_printk_bus(...)		atbm_printk(ATBM_PRINTK_MASK_BUS,__VA_ARGS__)
#define atbm_printk_scan(...)		atbm_printk(ATBM_PRINTK_MASK_SCAN,__VA_ARGS__)
#define atbm_printk_p2p(...)		atbm_printk(ATBM_PRINTK_MASK_P2P,__VA_ARGS__)
#define atbm_printk_mgmt(...)		atbm_printk(ATBM_PRINTK_MASK_MGMT,__VA_ARGS__)
#define atbm_printk_lmac(...)		atbm_printk(ATBM_PRINTK_MASK_LMAC,__VA_ARGS__)
#define atbm_printk_agg(...)		atbm_printk(ATBM_PRINTK_MASK_AGG,__VA_ARGS__)
#define atbm_printk_ap(...)			atbm_printk(ATBM_PRINTK_MASK_AP,__VA_ARGS__)
#define atbm_printk_sta(...)		atbm_printk(ATBM_PRINTK_MASK_STA,__VA_ARGS__)
#define atbm_printk_smt(...)		atbm_printk(ATBM_PRINTK_MASK_SMARTCONFIG,__VA_ARGS__)
#define atbm_printk_wext(...)		atbm_printk(ATBM_PRINTK_MASK_WEXT,__VA_ARGS__)
#define atbm_printk_tx(...)			atbm_printk(ATBM_PRINTK_MASK_TX,__VA_ARGS__)
#define atbm_printk_rx(...)			atbm_printk(ATBM_PRINTK_MASK_RX,__VA_ARGS__)
#define atbm_printk_pm(...)			atbm_printk(ATBM_PRINTK_MASK_PM,__VA_ARGS__)
#define atbm_printk_platform(...)	atbm_printk(ATBM_PRINTK_MASK_PLATFROM,__VA_ARGS__)
#define atbm_printk_bh(...)			atbm_printk(ATBM_PRINTK_MASK_BH,__VA_ARGS__)
#define atbm_printk_cfg(...)		atbm_printk(ATBM_PRINTK_MASK_CFG80211,__VA_ARGS__)
#define atbm_printk_debug(...)		atbm_printk(ATBM_PRINTK_MASK_DEBUG,__VA_ARGS__)
#define atbm_printk_always(fmt,arg...)		printk(KERN_ERR ATBM_TAG fmt,##arg)

void dump_mem(u8 *data, int len);

#ifdef TIME_DEBUG
#define JIFFIES_INIT_MAX_CNT   (12)
#define JIFFIES_EXIT_MAX_CNT   (12)
#endif

#endif /* ATBM_APOLLO_DEBUG_H_INCLUDED */
