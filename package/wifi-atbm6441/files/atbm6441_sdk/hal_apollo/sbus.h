/*
 * Common sbus abstraction layer interface for apollo wireless driver
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

#ifndef ATBM_APOLLO_SBUS_H
#define ATBM_APOLLO_SBUS_H
#include "apollo_plat.h"
/*
 * sbus priv forward definition.
 * Implemented and instantiated in particular modules.
 */
struct sbus_priv;

typedef void (*sbus_irq_handler)(void *priv);
typedef void (*sbus_callback_handler)(void *priv,void * arg);


struct sbus_ops {
#ifndef SPI_BUS
	int (*sbus_memcpy_fromio)(struct sbus_priv *self, unsigned int addr,void *dst, int count);/*rx queue mode*/
	int (*sbus_memcpy_toio)(struct sbus_priv *self, unsigned int addr,const void *src, int count);/*tx queue mode*/
	int (*sbus_read_async)(struct sbus_priv *self, unsigned int addr,void *dst, int count,sbus_callback_handler hander);/*rx queue mode*/
	int (*sbus_write_async)(struct sbus_priv *self, unsigned int addr,const void *src, int count,sbus_callback_handler hander);/*tx queue mode*/
	int (*sbus_read_sync)(struct sbus_priv *self, unsigned int addr, void *dst, int len);/*read register,download firmware,len <=256*/
	int (*sbus_write_sync)(struct sbus_priv *self, unsigned int addr, const void *src, int len);/*write register,download firmware,len <=256*/
	void (*lock)(struct sbus_priv *self);
	void (*unlock)(struct sbus_priv *self);	
	int (*irq_subscribe)(struct sbus_priv *self, sbus_irq_handler handler,
				void *priv);
	int (*irq_unsubscribe)(struct sbus_priv *self);
	int (*reset)(struct sbus_priv *self);
	u32 (*align_size)(struct sbus_priv *self, u32 size);
	int (*power_mgmt)(struct sbus_priv *self, bool suspend);
	int (*set_block_size)(struct sbus_priv *self, u32 size);
	void (*wtd_wakeup)( struct sbus_priv *self);
	int (*usb_lock_reset)(struct sbus_priv *self);
	#ifdef ATBM_USB_RESET
	int (*usb_reset)(struct sbus_priv *self);
	#endif
	int (*lmac_restart)(struct sbus_priv *self);
	int (*bootloader_debug_config)(struct sbus_priv *self,u16 enable);	
	int (*lmac_start)(struct sbus_priv *self);
	int (*ep0_cmd)(struct sbus_priv *self);
	int (*sbus_reset_chip)(struct sbus_priv *self);
	int (*abort)(struct sbus_priv *self);
	int (*sbus_wsm_write)(struct sbus_priv *self);
	int (*sbus_data_write)(struct sbus_priv *self);
	int (*sbus_init)(struct sbus_priv *self);
	int (*sbus_deinit)(struct sbus_priv *self);
	int (*sbus_wait_data_xmited)(struct sbus_priv *self);
	int (*sbus_xmit_func_init)(struct sbus_priv *self);
	int (*sbus_xmit_func_deinit)(struct sbus_priv *self);
	int (*sbus_xmit_schedule)(struct sbus_priv *self);
	int (*sbus_rev_func_init)(struct sbus_priv *self);
	int (*sbus_rev_func_deinit)(struct sbus_priv *self);
	int (*sbus_rev_schedule)(struct sbus_priv *self);
	int (*sbus_bh_suspend)(struct sbus_priv *self);
	int (*sbus_bh_resume)(struct sbus_priv *self);
	int (*sbus_rev_giveback)(struct sbus_priv *self,void *giveback);
#else
	u32 (*align_size)(struct sbus_priv *self, u32 size);
	int (*set_block_size)(struct sbus_priv *self, u32 size);
	int (*irq_subscribe)(struct sbus_priv *self, sbus_irq_handler handler,
				void *priv);
	int (*irq_unsubscribe)(struct sbus_priv *self);
	int (*reset)(struct sbus_priv *self);
	void (*lock)(struct sbus_priv *self);
	void (*unlock)(struct sbus_priv *self);
	int (*power_mgmt)(struct sbus_priv *self, bool suspend);

	int (*sbus_read_data)(struct sbus_priv *self, void *rx, size_t rx_len);
	int (*sbus_write_data)(struct sbus_priv *self,const void *tx, size_t tx_len);
	int (*sbus_write_firmware)(struct sbus_priv *self,unsigned int addr, const void *src, int count);
	int (*sbus_read_status)(struct sbus_priv *self, u32 *status, size_t tx_len);
	int (*sbus_read_channelflag)(struct sbus_priv *self, u32 *channelflag);
	int (*sbus_update_channelflag)(struct sbus_priv *self);
	int (*sbus_read_ready)(struct sbus_priv *self, u32 *ready);
	int (*sbus_reset_cpu)(struct sbus_priv *self);
	int (*sbus_shutdown_wlan)(struct sbus_priv *self);
	int (*sbus_reset_chip)(struct sbus_priv *self);
	int (*bootloader_debug_config)(struct sbus_priv *self,u16 enable);	
	int (*sbus_wsm_write)(struct sbus_priv *self);
	int (*sbus_data_write)(struct sbus_priv *self);
	int (*sbus_init)(struct sbus_priv *self);
	int (*sbus_deinit)(struct sbus_priv *self);
	int (*sbus_xmit_func_init)(struct sbus_priv *self);
	int (*sbus_xmit_func_deinit)(struct sbus_priv *self);
	int (*sbus_xmit_schedule)(struct sbus_priv *self);
	int (*sbus_rev_func_init)(struct sbus_priv *self);
	int (*sbus_rev_func_deinit)(struct sbus_priv *self);
	int (*sbus_rev_schedule)(struct sbus_priv *self);
	int (*sbus_bh_suspend)(struct sbus_priv *self);
	int (*sbus_bh_resume)(struct sbus_priv *self);
	int (*sbus_rev_giveback)(struct sbus_priv *self,void *giveback);
#endif
};



#if (PROJ_TYPE>=ARES_B)
enum HW_RESET_TYPE{
	HW_RESET_HIF,//clean channels
	HW_RESET_HIF_SYSTEM,
	HW_RESET_HIF_SYSTEM_USB,
	HW_HOLD_CPU,
	HW_RUN_CPU,
	HW_RESET_HIF_SYSTEM_CPU,
};
#define HW_RESET_REG_CPU   				BIT(16)
#define HW_RESET_REG_HIF   				BIT(17)
#define HW_RESET_REG_SYS   				BIT(18)
#define HW_RESRT_REG_CHIP  				BIT(19)
#define HW_RESET_REG_NEED_IRQ_TO_LMAC	BIT(20)
int atbm_usb_ep0_hw_reset_cmd(struct sbus_priv *self,enum HW_RESET_TYPE type,bool irq_lmac);
#endif //(PROJ_TYPE>=ARES_B)
void atbm_usb_kill_all_rxurb(struct sbus_priv *self);
void atbm_usb_kill_all_txurb(struct sbus_priv *self);
int __atbm_usb_suspend(struct sbus_priv *self);
int __atbm_usb_resume(struct sbus_priv *self);

#endif /* ATBM_APOLLO_SBUS_H */
