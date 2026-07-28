/*
 * Low-level device IO routines for altobeam apollo wifi drivers
 *
 * Copyright (c) 2016, altobeam
 *
 * Based on:
 * Copyright (c) 2010, stericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * Based on:
 * ST-Ericsson UMAC CW1200 driver, which is
 * Copyright (c) 2010, ST-Ericsson
 * Author: Ajitpal Singh <ajitpal.singh@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifdef LINUX_OS
#include <linux/types.h>
#include <linux/module.h>
#endif

#include "apollo.h"
#include "hwio.h"
#include "sbus.h"
#include "debug.h"
#include "dcxo_dpll.h"
#include "wsm.h"
 /*config dcxo value*/
 char *dcxo_value="default";
 
 module_param(dcxo_value,charp,0644);
 MODULE_PARM_DESC(dcxo_value,"Need to config dcxo reg");
 
 /*config dpll value*/
 char *dpll_value="default";
 module_param(dpll_value,charp,0644);
 MODULE_PARM_DESC(dpll_value,"Need to config dpll reg");

extern int atbm_sdio_memcpy_fromio_for_sleep(struct sbus_priv *self,
				     unsigned int addr,
				     void *dst, int count);
extern int atbm_sdio_memcpy_toio_for_sleep(struct sbus_priv *self,
				   unsigned int addr,
				   const void *src, int count);

 /* Sdio addr is 4*spi_addr */
#define SPI_REG_ADDR_TO_SDIO(spi_reg_addr) ((spi_reg_addr) << 2)

#define SDIO_INPUT_64 1
#define SDIO_ADDR17BIT(buf_id, mpf, force, reg_id_ofs) \
				((((buf_id)    & 0x7F) << 6) \
				| (((force)        & 1) << 5) \
				| (((reg_id_ofs) & 0x1F) << 0))


static int __atbm_reg_read(struct atbm_common *hw_priv, u16 addr,
				void *buf, u32 buf_len)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;

	/* Check if buffer is aligned to 4 byte boundary */
	if (WARN_ON(((unsigned long)buf & 3) && (buf_len > 4))) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			   "%s: buffer is not aligned.\n", __func__);
		return -EINVAL;
	}

	/* Convert to SDIO Register Address */
	addr_sdio = SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(0, 0, 0, addr_sdio);

	BUG_ON(!hw_priv->sbus_ops);
	return hw_priv->sbus_ops->sbus_read_sync(hw_priv->sbus_priv,
						  sdio_reg_addr_17bit,
						  buf, buf_len);
}

static int __atbm_reg_write(struct atbm_common *hw_priv, u16 addr,
				const void *buf, u32 buf_len)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;


	/* Convert to SDIO Register Address */
	addr_sdio = SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(0, 0, 0, addr_sdio);
	//printk("__atbm_reg_write sdio_reg_addr_17bit 0x%x,addr_sdio 0x%x,len %d,buf_id %d\n",sdio_reg_addr_17bit,addr_sdio,buf_len,buf_id);

	BUG_ON(!hw_priv->sbus_ops);
	return hw_priv->sbus_ops->sbus_write_sync(hw_priv->sbus_priv,
						sdio_reg_addr_17bit,
						buf, buf_len);
}

int __atbm_reg_read_for_sleep(struct atbm_common *hw_priv, u16 addr,
				void *buf, u32 buf_len)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;

	/* Check if buffer is aligned to 4 byte boundary */
	if (WARN_ON(((unsigned long)buf & 3) && (buf_len > 4))) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			   "%s: buffer is not aligned.\n", __func__);
		return -EINVAL;
	}

	/* Convert to SDIO Register Address */
	addr_sdio = SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(0, 0, 0, addr_sdio);

	return atbm_sdio_memcpy_fromio_for_sleep(hw_priv->sbus_priv, sdio_reg_addr_17bit, buf, buf_len);
}

int __atbm_reg_write_for_sleep(struct atbm_common *hw_priv, u16 addr,
				const void *buf, u32 buf_len)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;

	/* Convert to SDIO Register Address */
	addr_sdio = SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(0, 0, 0, addr_sdio);
	//printk("__atbm_reg_write sdio_reg_addr_17bit 0x%x,addr_sdio 0x%x,len %d,buf_id %d\n",sdio_reg_addr_17bit,addr_sdio,buf_len,buf_id);

	return atbm_sdio_memcpy_toio_for_sleep(hw_priv->sbus_priv, sdio_reg_addr_17bit, buf, buf_len);
}

static int __atbm_data_read(struct atbm_common *hw_priv, u16 addr,
				void *buf, u32 buf_len, int buf_id)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;

	/* Check if buffer is aligned to 4 byte boundary */
	if (WARN_ON(((unsigned long)buf & 3) && (buf_len > 4))) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			   "%s: buffer is not aligned.\n", __func__);
		return -EINVAL;
	}

	/* Convert to SDIO Register Address */
	addr_sdio = SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(buf_id, 0, hw_priv->buf_force_tx, addr_sdio);
	hw_priv->buf_force_tx=0;

	BUG_ON(!hw_priv->sbus_ops);
	return hw_priv->sbus_ops->sbus_memcpy_fromio(hw_priv->sbus_priv,
						  sdio_reg_addr_17bit,
						  buf, buf_len);
}

static int __atbm_data_write(struct atbm_common *hw_priv, u16 addr,
				const void *buf, u32 buf_len, int buf_id)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;


	/* Convert to SDIO Register Address */
	addr_sdio = SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(buf_id, 0, hw_priv->buf_force_rx, addr_sdio);
	hw_priv->buf_force_rx=0;

	BUG_ON(!hw_priv->sbus_ops);
	return hw_priv->sbus_ops->sbus_memcpy_toio(hw_priv->sbus_priv,
						sdio_reg_addr_17bit,
						buf, buf_len);
}

static inline int __atbm_reg_read_32(struct atbm_common *hw_priv,
					u16 addr, u32 *val)
{
	return __atbm_reg_read(hw_priv, addr, val, 4);
}

static inline int __atbm_reg_write_32(struct atbm_common *hw_priv,
					u16 addr, u32 val)
{
	return __atbm_reg_write(hw_priv, addr, &val, sizeof(val));
}

int __atbm_reg_write_dpll(struct atbm_common *hw_priv, u16 addr,
		    const void *buf, u32 buf_len,int buf_id)
{
	u16 addr_sdio;
	u32 sdio_reg_addr_17bit ;

	/* Check if buffer is aligned to 4 byte boundary */
	if (WARN_ON(((unsigned long)buf & 3) && (buf_len > 4))) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			   "%s: buffer is not aligned.\n", __func__);
		return -EINVAL;
	}

	/* Convert to SDIO Register Address */
	addr_sdio = addr;//SPI_REG_ADDR_TO_SDIO(addr);
	sdio_reg_addr_17bit = SDIO_ADDR17BIT(buf_id, 0, 0, addr_sdio);

	BUG_ON(!hw_priv->sbus_ops);
	return hw_priv->sbus_ops->sbus_write_sync(hw_priv->sbus_priv,
						  sdio_reg_addr_17bit,
						  buf, buf_len);

}
int __atbm_reg_read_dpll(struct atbm_common *hw_priv, u16 addr,
		     const void *buf, u32 buf_len,int buf_id)
{
		u16 addr_sdio;
		u32 sdio_reg_addr_17bit ;

		//atbm_dbg(ATBM_APOLLO_DBG_MSG, "%x,addr,func=s\n",addr,__func__);

		/* Convert to SDIO Register Address */
		addr_sdio = addr;//SPI_REG_ADDR_TO_SDIO(addr);
		sdio_reg_addr_17bit = SDIO_ADDR17BIT(buf_id, 0, 0, addr_sdio);
		//atbm_dbg(ATBM_APOLLO_DBG_MSG, "%x,sdio_reg_addr_17bit,func=%s\n",sdio_reg_addr_17bit,__func__);

		BUG_ON(!hw_priv->sbus_ops);
		return hw_priv->sbus_ops->sbus_read_sync(hw_priv->sbus_priv,
							sdio_reg_addr_17bit,
							(void*)buf, buf_len);


}
int atbm_reg_read_dpll(struct atbm_common *hw_priv, u16 addr, void *buf,
			u32 buf_len)
{
	int ret;
	BUG_ON(!hw_priv->sbus_ops);
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	ret = __atbm_reg_read_dpll(hw_priv, addr, buf, buf_len, 0);
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}

int atbm_reg_write_dpll(struct atbm_common *hw_priv, u16 addr, const void *buf,
			u32 buf_len)
{
	int ret;
	BUG_ON(!hw_priv->sbus_ops);
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	ret = __atbm_reg_write_dpll(hw_priv, addr, buf, buf_len, 0);
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}


int atbm_reg_read(struct atbm_common *hw_priv, u16 addr, void *buf,
			u32 buf_len)
{
	int ret;
	BUG_ON(!hw_priv->sbus_ops);
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	ret = __atbm_reg_read(hw_priv, addr, buf, buf_len);
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}

int atbm_reg_write(struct atbm_common *hw_priv, u16 addr, const void *buf,
			u32 buf_len)
{
	int ret;
	BUG_ON(!hw_priv->sbus_ops);
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	ret = __atbm_reg_write(hw_priv, addr, buf, buf_len);
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}

int atbm_reg_read_for_sleep(struct atbm_common *hw_priv, u16 addr, void *buf,
			u32 buf_len)
{
	return __atbm_reg_read_for_sleep(hw_priv, addr, buf, buf_len);
}

int atbm_reg_write_for_sleep(struct atbm_common *hw_priv, u16 addr, const void *buf,
			u32 buf_len)
{
	return __atbm_reg_write_for_sleep(hw_priv, addr, buf, buf_len);
}

int atbm_reg_read_unlock(struct atbm_common *hw_priv, u16 addr, void *buf,
			u32 buf_len)
{
	int ret;
	int retry=0;
	BUG_ON(!hw_priv->sbus_ops);
	while (retry <= 3) {
		ret = __atbm_reg_read(hw_priv, addr, buf, buf_len);
		if(ret){
			atbm_printk_err("%s\n",__func__);
			retry++;
		}else{
			break;
		}
	}
	return ret;
}

int atbm_reg_write_unlock(struct atbm_common *hw_priv, u16 addr, const void *buf,
			u32 buf_len)
{
	int ret;
	int retry=0;
	BUG_ON(!hw_priv->sbus_ops);
	while (retry <= 3) {
		ret = __atbm_reg_write(hw_priv, addr, buf, buf_len);
		if(ret){
			atbm_printk_err("%s\n",__func__);
			retry++;
		}else{
			break;
		}
	}
	return ret;
}
int atbm_data_read_unlock(struct atbm_common *hw_priv, void *buf, u32 buf_len)
{
	int ret = -1, retry = 1;
	int buf_id_rx = hw_priv->buf_id_rx;
	
	while (retry <= MAX_RETRY) {
		ret = __atbm_data_read(hw_priv,
				ATBM_HIFREG_IN_OUT_QUEUE_REG_ID, buf,
				buf_len, buf_id_rx + 1);
		if (!ret) {
			buf_id_rx = (buf_id_rx + 1) & 3;
			hw_priv->buf_id_rx = buf_id_rx;
			break;
		} else {
			retry++;
			mdelay(1000);
			atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s,error :[%d]\n",
					__func__, ret);
		}
	}

	return ret;
}
int atbm_data_read(struct atbm_common *hw_priv, void *buf, u32 buf_len)
{
	int ret;
	BUG_ON(!hw_priv->sbus_ops);
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	{
		ret = atbm_data_read_unlock(hw_priv,buf,buf_len);
	}
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}

#if (PROJ_TYPE>=ARES_B)
//just ARESB have this function
//used this function to clear sdio rtl bug register
// if not do this sdio direct mode (wr/read reigster) will not work
int atbm_data_force_write(struct atbm_common *hw_priv, const void *buf,
                        size_t buf_len)
{
        int ret, retry = 1;
        int buf_id_tx;
        BUG_ON(!hw_priv->sbus_ops);
        hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
        buf_id_tx = ((hw_priv->buf_id_tx-1)&0x3f)+64;
		atbm_printk_always("buf_id_tx =%d %s\n",buf_id_tx,__func__);
        while (retry <= MAX_RETRY) {
                ret = __atbm_data_write(hw_priv,
                                ATBM_HIFREG_IN_OUT_QUEUE_REG_ID, buf,
                                buf_len, buf_id_tx);

                if (!ret) {
                        buf_id_tx =  ((buf_id_tx + hw_priv->buf_id_offset)&0x3f);
                        hw_priv->buf_id_tx = buf_id_tx;
                        break;
                } else {
                        retry++;
                        mdelay(1000);
                        atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s,%d,error :[%d]\n",
                                        __func__, __LINE__, ret);
                }
        }
        hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
        return ret;
}
#endif //#if (PROJ_TYPE>=ARES_B)
//sdio
int atbm_data_write_unlock(struct atbm_common *hw_priv, const void *buf,
			size_t buf_len)
{
	int ret = -1, retry = 1;
	int buf_id_tx;

	buf_id_tx = hw_priv->buf_id_tx;
	while (retry <= MAX_RETRY) {
		ret = __atbm_data_write(hw_priv,
				ATBM_HIFREG_IN_OUT_QUEUE_REG_ID, buf,
				buf_len, buf_id_tx);

		if (!ret) {
		//	buf_id_tx =  ((buf_id_tx + hw_priv->buf_id_offset) >63)?((buf_id_tx + hw_priv->buf_id_offset)-64): (buf_id_tx + hw_priv->buf_id_offset) ;
			buf_id_tx =  ((buf_id_tx + hw_priv->buf_id_offset)&0x3f);
			hw_priv->buf_id_tx = buf_id_tx;
			break;
		} else {
			retry++;
			mdelay(1000);
			atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s,%d,error :[%d]\n",
					__func__, __LINE__, ret);
		}
	}

	return ret;
}
int atbm_data_write(struct atbm_common *hw_priv, const void *buf,
			size_t buf_len)
{
	int ret;

	BUG_ON(!hw_priv->sbus_ops);
	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
//	printk("buf_id =%d,buf_id_offset=%d\n",buf_id_tx,hw_priv->buf_id_offset);
	ret = atbm_data_write_unlock(hw_priv,buf,buf_len);
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}


//usb
int atbm_indirect_read(struct atbm_common *hw_priv, u32 addr, void *buf,
			 u32 buf_len, u32 prefetch, u16 port_addr)
{
	u32 val32 = 0;
	int i, ret;

	if ((buf_len / 2) >= 0x1000) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't read more than 0xfff words.\n",
				__func__);
		WARN_ON(1);
		return -EINVAL;
		goto out;
	}

	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);
	/* Write address */
	ret = __atbm_reg_write_32(hw_priv, ATBM_HIFREG_SRAM_BASE_ADDR_REG_ID,
				    addr);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't write address register.\n",
				__func__);
		goto out;
	}

	/* Read CONFIG Register Value - We will read 32 bits */
	ret = __atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't read config register.\n",
				__func__);
		goto out;
	}

	/* Set PREFETCH bit */
	ret = __atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,
					val32 | prefetch);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't write prefetch bit.\n",
				__func__);
		goto out;
	}

	/* Check for PRE-FETCH bit to be cleared */
	for (i = 0; i < 20; i++) {
		ret = __atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,
					   &val32);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
					"%s: Can't check prefetch bit.\n",
					__func__);
			goto out;
		}
		if (!(val32 & prefetch))
			break;

		mdelay(i);
	}

	if (val32 & prefetch) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Prefetch bit is not cleared.\n",
				__func__);
		goto out;
	}

	/* Read data port */
	ret = __atbm_reg_read(hw_priv, port_addr, buf, buf_len);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't read data port.\n",
				__func__);
		goto out;
	}

out:
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}

int atbm_apb_write(struct atbm_common *hw_priv, u32 addr, const void *buf,
			u32 buf_len)
{
	int ret;

	if ((buf_len / 2) >= 0x1000) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't wrire more than 0xfff words.\n",
				__func__);
		WARN_ON(1);
		return -EINVAL;
	}

	hw_priv->sbus_ops->lock(hw_priv->sbus_priv);

	/* Write address */
	ret = __atbm_reg_write_32(hw_priv, ATBM_HIFREG_SRAM_BASE_ADDR_REG_ID,
				    addr);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't write address register.\n",
				__func__);
		goto out;
	}

	/* Write data port */
	ret = __atbm_reg_write(hw_priv, ATBM_HIFREG_SRAM_DPORT_REG_ID,
					buf, buf_len);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s: Can't write data port.\n",
				__func__);
		goto out;
	}

out:
	hw_priv->sbus_ops->unlock(hw_priv->sbus_priv);
	return ret;
}
int atbm_indirect_read_unlock(struct atbm_common *hw_priv, u32 addr, void *buf,
			 u32 buf_len, u32 prefetch, u16 port_addr)
{
	u32 val32 = 0;
	int i, ret;
	int retry=0;
	if ((buf_len / 2) >= 0x1000) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't read more than 0xfff words.\n",
				__func__);
		WARN_ON(1);
		return -EINVAL;
		goto out;
	}
	/* Write address */
	
	while(retry<=3){
		ret = __atbm_reg_write_32(hw_priv, ATBM_HIFREG_SRAM_BASE_ADDR_REG_ID,
					    addr);
			if (ret < 0) {
				atbm_dbg(ATBM_APOLLO_DBG_ERROR,
						"%s: Can't write address register.\n",
						__func__);
				retry++;
			}else{
				break;
			}
	}

	/* Read CONFIG Register Value - We will read 32 bits */
	retry=0;
	while(retry<=3){
		ret = __atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
		if (ret <0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
					"%s: Can't read config register.\n",
					__func__);
			retry++;
		}else{
			break;
		}
	}

	/* Set PREFETCH bit */
	retry=0;
	while(retry<=3){
	ret = __atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,
						val32 | prefetch);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
					"%s: Can't write prefetch bit.\n",
					__func__);
			retry++;
		}else{
			break;
		}
	}

	/* Check for PRE-FETCH bit to be cleared */
	for (i = 0; i < 20; i++) {
		ret = __atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,
					   &val32);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
					"%s: Can't check prefetch bit.\n",
					__func__);
			mdelay(i);
			continue;
		}
		if (!(val32 & prefetch))
			break;

		mdelay(i);
	}

	if (val32 & prefetch) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Prefetch bit is not cleared.\n",
				__func__);
		goto out;
	}

	/* Read data port */
	retry=0;
	while(retry<=3){
		ret = __atbm_reg_read(hw_priv, port_addr, buf, buf_len);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
					"%s: Can't read data port.\n",
					__func__);
			retry++;
		}else{
			break;
		}
	}
out:
	return ret;
}
int atbm_apb_write_reset(struct atbm_common *hw_priv, u32 addr, const void *buf,
			u32 buf_len)
{
	int ret;

	if ((buf_len / 2) >= 0x1000) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't wrire more than 0xfff words.\n",
				__func__);
		WARN_ON(1);
		return -EINVAL;
	}
	/* Write address */
	ret = __atbm_reg_write_32(hw_priv, ATBM_HIFREG_SRAM_BASE_ADDR_REG_ID,
				    addr);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: Can't write address register.\n",
				__func__);
		goto out;
	}

	/* Write data port */
	ret = __atbm_reg_write(hw_priv, ATBM_HIFREG_SRAM_DPORT_REG_ID,
					buf, buf_len);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s: Can't write data port.\n",
				__func__);
		goto out;
	}
out:
	return ret;
}
int atbm_fw_write(struct atbm_common *priv, u32 addr, const void *buf,
                        u32 buf_len)
{
	return atbm_ahb_write(priv,  addr, buf, buf_len);		
}


int atbm_ahb_write(struct atbm_common *priv, u32 addr, const void *buf,
                        u32 buf_len)
{
        int ret;
		//printk(KERN_ERR "%s: addr %x\n",__func__,addr);
        if (buf_len  >= 512) {
                atbm_dbg(ATBM_APOLLO_DBG_ERROR,
                                "%s: Can't wrire more than 0xfff words.\n",
                                __func__);
                WARN_ON(1);
				atbm_printk_err("%s:EXIT (1) \n",__func__);
                return -EINVAL;
        }

        priv->sbus_ops->lock(priv->sbus_priv);

        /* Write address */
        ret = __atbm_reg_write_32(priv, ATBM_HIFREG_SRAM_BASE_ADDR_REG_ID, addr);
        if (ret < 0) {
                atbm_dbg(ATBM_APOLLO_DBG_ERROR,
                                "%s: Can't write address register.\n",
                                __func__);
                goto out;
        }

        /* Write data port */
        ret = __atbm_reg_write(priv, ATBM_HIFREG_AHB_DPORT_REG_ID,
                                        buf, buf_len);
        if (ret < 0) {
                atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s: Can't write data port.\n",
                                __func__);
                goto out;
        }

out:
        priv->sbus_ops->unlock(priv->sbus_priv);

        return ret;
}
int atbm_ahb_write_unlock(struct atbm_common *priv, u32 addr, const void *buf,
                        u32 buf_len)
{
        int ret;
		int retry=0;
		//printk(KERN_ERR "%s: addr %x\n",__func__,addr);
        if (buf_len  >= 512) {
                atbm_dbg(ATBM_APOLLO_DBG_ERROR,
                                "%s: Can't wrire more than 0xfff words.\n",
                                __func__);
                WARN_ON(1);
				atbm_printk_err("%s:EXIT (1) \n",__func__);
                return -EINVAL;
        }
        /* Write address */
		while(retry<=3){
	        ret = __atbm_reg_write_32(priv, ATBM_HIFREG_SRAM_BASE_ADDR_REG_ID, addr);
	        if (ret < 0) {
	                atbm_dbg(ATBM_APOLLO_DBG_ERROR,
	                                "%s: Can't write address register.\n",
	                                __func__);
					retry++;
	        }else{
				break;
			}
		}
		retry=0;
        /* Write data port */
		while(retry<=3){
	        ret = __atbm_reg_write(priv, ATBM_HIFREG_AHB_DPORT_REG_ID,
	                                        buf, buf_len);
	        if (ret < 0) {
	                atbm_dbg(ATBM_APOLLO_DBG_ERROR, "%s: Can't write data port.\n",
	                                __func__);
					retry++;
	        }else{
				break;
			}
		}
//out:
        return ret;
}

int atbm_direct_read_reg_32(struct atbm_common *hw_priv, u32 addr, u32 *val)
{
    int ret;
	u32 val32;
	u32 orig_config_data = 0;

	/* Checking for access mode */
	ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't read " \
			"config register.\n", __func__);
		goto out1;
	}
	orig_config_data = val32;
	val32 |= ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT;
	ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}
	ret = atbm_ahb_read_32(hw_priv,addr,val);
	//printk("val=%x\n",val);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}

out:
	ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,orig_config_data);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't write " \
			"config register.\n", __func__);
		goto out;
	}
out1:
	return ret;
}


int atbm_direct_write_reg_32(struct atbm_common *hw_priv, u32 addr, u32 val)
{
    int ret;
	u32 val32;
	u32 orig_config_data = 0;

	/* Checking for access mode */
	ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't read " \
			"config register.\n", __func__);
		goto out1;
	}
	orig_config_data = val32;
	val32 |= ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT;
	ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}
	ret = atbm_ahb_write_32(hw_priv,addr,val);

	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}

out:
	ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,orig_config_data);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't write " \
			"config register.\n", __func__);
		goto out;
	}
out1:
	return ret;
}
int atbm_direct_write_unlock(struct atbm_common *hw_priv, u32 addr, u32 val)
{
    int ret;
	u32 val32;
	u32 orig_config_data = 0;

	/* Checking for access mode */
	ret = atbm_reg_read_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't read " \
			"config register.\n", __func__);
		goto out1;
	}
	orig_config_data = val32;
	val32 |= ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT;
	ret = atbm_reg_write_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}
	ret = atbm_ahb_write_unlock_32(hw_priv,addr,val);

	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}

out:
	ret = atbm_reg_write_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,orig_config_data);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't write " \
			"config register.\n", __func__);
		goto out;
	}
out1:
	return ret;
}
int atbm_direct_read_unlock(struct atbm_common *hw_priv, u32 addr, u32 *val)
{
    int ret;
	u32 val32;
	u32 orig_config_data = 0;

	/* Checking for access mode */
	ret = atbm_reg_read_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't read " \
			"config register.\n", __func__);
		goto out1;
	}
	orig_config_data = val32;
	val32 |= ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT;
	ret = atbm_reg_write_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}
	ret = atbm_ahb_read_unlock_32(hw_priv,addr,val);
	//printk("val=%x\n",val);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s:  can't write " \
			"config register.\n", __func__);
		goto out;
	}

out:
	ret = atbm_reg_write_unlock_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,orig_config_data);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't write " \
			"config register.\n", __func__);
		goto out;
	}
out1:
	return ret;
}

void __atbm_irq_dbgPrint(struct atbm_common *priv)
{
	u32 val32;
	int ret;

	ret = __atbm_reg_read_32(priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		pr_err("Can't read config register.\n");
		return;
	}
	atbm_printk_debug("ATBM_HIFREG_CONFIG_REG_ID=0x%x\n", val32);

	return;
}

int __atbm_irq_enable(struct atbm_common *priv, int enable)
{
	u32 val32;
	int ret;

	ret = __atbm_reg_read_32(priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		pr_err("Can't read config register.\n");
		return ret;
	}

	if (enable){
		if(val32 & ATBM_HIFREG_CONF_IRQ_RDY_ENABLE)
			return ret;
		val32 |= ATBM_HIFREG_CONF_IRQ_RDY_ENABLE;

	}
	else {
		if((val32 & ATBM_HIFREG_CONF_IRQ_RDY_ENABLE)==0)
			return ret;
		val32 &= ~ATBM_HIFREG_CONF_IRQ_RDY_ENABLE;
	}
	ret = __atbm_reg_write_32(priv, ATBM_HIFREG_CONFIG_REG_ID, val32);
	if (ret < 0) {
		pr_err("Can't write config register.\n");
		return ret;
	}

	return 0;
}



//atbm_dcxo_dpll_initial
int atbm_before_load_firmware(struct atbm_common *hw_priv)
{
#if (PROJ_TYPE>=ARES_A)
	#define ATBM_VOL_L					(-1)
#else
	#define ATBM_VOL_L					(10)
#endif
	int ret=0;
	int i;
	u32 val32;
	u16 val16;
	int major_revision;

	u32 config_reg;
	
	FUNC_ENTER();

	BUG_ON(!hw_priv);	
	#if (ATBM_VOL_L == 10)
	#pragma message ("1.0v")
	atbm_printk_init("+++++++++++++++++1.0v+++++++++++++++++++\n");
	ret = atbm_direct_write_reg_32(hw_priv,0xacc0178,0x3400071);
	if(ret<0)
		atbm_printk_err("write 0xacc0178 err\n");
#endif
retry:
	/* Read CONFIG Register Value - We will read 32 bits */
	ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't read config register.\n", __func__);
		goto out;
	}

	hw_priv->hw_type = atbm_get_hw_type(val32, &major_revision);


	if (hw_priv->hw_type < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: can't deduct hardware type.\n", __func__);
		ret = -ENOTSUPP;
		goto out;
	}


	/* Set wakeup bit in device */
	ret = atbm_reg_read_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, &val16);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: set_wakeup: can't read " \
			"control register.\n", __func__);
		goto out;
	}

	ret = atbm_reg_write_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID,
		val16 | ATBM_HIFREG_CONT_WUP_BIT);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: set_wakeup: can't write " \
			"control register.\n", __func__);
		goto out;
	}
#ifdef TEST_DCXO_CONFIG
		/*start config dcxo */
			ret=atbm_config_dcxo(hw_priv,dcxo_value,PROJ_TYPE,DCXO_TYPE,DPLL_CLOCK);
			if (ret<0){
				atbm_dbg(ATBM_APOLLO_DBG_MSG, "atbm_config_dcxo error.\n");
			}
#endif
#ifdef TEST_DPLL_CONFIG
		/*start config dpll */
		ret = atbm_config_dpll(hw_priv,dpll_value,PROJ_TYPE,DPLL_CLOCK);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_MSG, "atbm_config_dpll error.\n");
		 }
#endif
#ifdef DCXO_USE_SMU_REG
			/*The fifth step store dpll value to smu*/
			if ((PROJ_TYPE==ATHENA_B)|| (PROJ_TYPE>=ARES_A)){
				atbm_set_config_to_smu_apolloC(hw_priv,DPLL_CLOCK);
			}else{
				atbm_set_config_to_smu_apolloB(hw_priv,DPLL_CLOCK);
			}
			/*start shut down system*/
			ret =atbm_system_done(hw_priv);
			if (ret<0){
				atbm_dbg(ATBM_APOLLO_DBG_MSG, "atbm_system_done error.\n");
			}
#else		
			atbm_printk_err("%s:do not set config to smu\n",__func__);
#endif


	atbm_dbg(ATBM_APOLLO_DBG_MSG, "atbm_wait_wlan_rdy  Wait for wakeup .\n");
	/* Set wakeup bit in device */
	ret = atbm_reg_read_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, &val16);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: set_wakeup: can't read " \
			"control register.\n", __func__);
		goto out;
	}

	ret = atbm_reg_write_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, val16 | ATBM_HIFREG_CONT_WUP_BIT);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: set_wakeup: can't write " \
			"control register.\n", __func__);
		goto out;
	}

	/* Wait for wakeup */
	for (i = 0 ; i < 3000 ; i += 1 + i / 2) {
		ret = atbm_reg_read_16(hw_priv,
			ATBM_HIFREG_CONTROL_REG_ID, &val16);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: wait_for_wakeup: can't read " \
				"control register.\n", __func__);
			goto out;
		}

		if (val16 & ATBM_HIFREG_CONT_RDY_BIT) {
			atbm_dbg(ATBM_APOLLO_DBG_MSG,
				"WLAN device is ready.\n");
			break;
		}
		msleep(i);
	}

	if ((val16 & ATBM_HIFREG_CONT_RDY_BIT) == 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: wait_for_wakeup: device is not responding.\n",
			__func__);
		ret = -ETIMEDOUT;
		goto out;
	}

		
	
	atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &config_reg);
	if(config_reg & ATBM_HIFREG_PS_SYNC_SDIO_FLAG)
	{
		config_reg |= ATBM_HIFREG_PS_SYNC_SDIO_CLEAN;
		atbm_reg_write_32(hw_priv,ATBM_HIFREG_CONFIG_REG_ID,config_reg);
	}


	hw_priv->hw_revision = ATBM_APOLLO_REV_1601;

	/* set cpu reset ,cpu will stop */
	/* Checking for access mode */
	ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't read " \
			"config register.\n", __func__);
		goto out;
	}
	val32 |= ATBM_HIFREG_CONFIG_CPU_RESET_BIT|ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT;
	ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't write " \
			"config register.\n", __func__);
		goto out;
	}

	ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
	if (ret < 0) {
		atbm_dbg(ATBM_APOLLO_DBG_ERROR,
			"%s: enable_irq: can't read " \
			"config register.\n", __func__);
		goto out;
	}

	WARN_ON(!(val32 & ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT));
	//u32 testreg_uart;
#ifdef START_DCXO_CONFIG
	atbm_ahb_write_32(priv,0x18e00014,0x200);
	atbm_ahb_read_32(priv,0x18e00014,&val32_1);
	//atbm_ahb_read_32(priv,0x16400000,&testreg_uart);
	atbm_printk_bus("0x18e000e4-->%08x %08x\n",val32_1);
#endif//TEST_DCXO_CONFIG

out:
	if(ret != 0 ){
		u8 Dpll_val_suc_fail;
		ret=atbm_reg_write_8(hw_priv,0x18,0x51);
		if (ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_DCXO_DPLL,"%d:read action dpll_work_s & dpll_work_fail error",__LINE__);
			goto out;
		}
		ret =atbm_reg_read_8(hw_priv,0x19,&Dpll_val_suc_fail);
		atbm_printk_err("%s:Dpll_val_suc_fail(%x)\n",__func__,Dpll_val_suc_fail);
		atbm_reset_lmc_cpu(hw_priv);
		goto retry;
	}
#if (DPLL_CLOCK == DPLL_CLOCK_24M)
	{
		u32 reset_reg = 0;
		#pragma message("add delay before load fw")
		mdelay(100);
		ret = atbm_direct_read_reg_32(hw_priv,0x16100074,&reset_reg);
		atbm_printk_err("%s:read [0x16100074]=[%x],ret(%d)\n",__func__,reset_reg,ret);
		reset_reg |= BIT(0);
		ret = atbm_direct_write_reg_32(hw_priv,0x16100074,reset_reg);		
		atbm_printk_err("%s:write [0x16100074]=[%x],ret(%d)\n",__func__,reset_reg,ret);
		mdelay(100);
	}
#endif
	return ret;
}
//atbm_initial_irq
int atbm_after_load_firmware(struct atbm_common *hw_priv)
{
		int ret;
		//int i;
		u32 val32;
		u16 val16;

		//enable gpio irq register,may need move to lmac/apb.c	SMU_Init
		ret=atbm_ahb_read_32(hw_priv,0x161000ac,&val32);
		val32&=0xFFFFF7F8;
		val32|=BIT(12);
		ret=atbm_ahb_write_32(hw_priv,0x161000ac,val32);
		if(ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: enable_irq: can't read " \
				"config register.\n", __func__);

		}

#if (PROJ_TYPE==ARES_B)

		ret=atbm_ahb_read_32(hw_priv,0x1610102c,&val32);
		if(ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: 0x1610102c: can't read register.\n", __func__);
			goto out;
		}
		val32 &= ~(0xffff0000);
		val32 |= BIT(0) | BIT(1) | (0x1 << 16);
		ret=atbm_ahb_write_32(hw_priv,0x1610102c,val32);
		if(ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: 0x1610102c: can't write register.\n", __func__);
			goto out;
		}
		while(1)
		{
			ret=atbm_ahb_read_32(hw_priv,0x1610102c,&val32);
			if(ret<0){
				atbm_dbg(ATBM_APOLLO_DBG_ERROR,
					"%s: 0x1610102c: can't read register.\n", __func__);
				goto out;
			}
			if (val32 & BIT(16))
				break;
			msleep(1);
		}
#endif
		/* If device is CW1200 the IRQ enable/disable bits
		 * are in CONFIG register, clear cpu reset ,cpu will run */
		ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: enable_irq: can't read " \
				"config register.\n", __func__);
			goto unsubscribe;
		}
		val32 |= ATBM_HIFREG_CONF_IRQ_RDY_ENABLE;
		val32 &= ~ATBM_HIFREG_CONFIG_CPU_RESET_BIT;
		//enable data1 IRQ
		val32 &= ~ATBM_HIFREG_CONFIG_CLEAR_INT_BIT;
		ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,val32);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: enable_irq: can't write " \
				"config register.\n", __func__);
			goto unsubscribe;
		}
#if (PROJ_TYPE==ARES_B)
		ret=atbm_ahb_write_32(hw_priv,0x16100074,0x1);
		if(ret<0){
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: 0x1610102c: can't write register.\n", __func__);
			goto out;
		}
#endif
		
		//hare sdio + iot,let lmac know host initial done .add by wp
		//ret = atbm_ahb_read_32(hw_priv, SDIO_INIT_DONE_REG, &val32);
		
		//atbm_printk_init("SDIO_INIT_DONE_REG %x %x.\n",SDIO_INIT_DONE_REG,val32);
		//atbm_ahb_write_32(hw_priv,SDIO_INIT_DONE_REG,val32&(~BIT(11)));

		/* Configure device for MESSSAGE MODE */
		ret = atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: set_mode: can't read config register.\n",
				__func__);
			goto unsubscribe;
		}
		ret = atbm_reg_write_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID,
			val32 & ~ATBM_HIFREG_CONFIG_ACCESS_MODE_BIT);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: set_mode: can't write config register.\n",
				__func__);
			goto unsubscribe;
		}
		/* Unless we read the CONFIG Register we are
		 * not able to get an interrupt */
		mdelay(10);
		atbm_reg_read_32(hw_priv, ATBM_HIFREG_CONFIG_REG_ID, &val32);
		
		//hare sdio + iot,let lmac know host initial done .add by wp
		/* Set wakeup bit in device */
		ret = atbm_reg_read_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, &val16);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: set_wakeup: can't read " \
				"control register.\n", __func__);
			goto out;
		}
		
		ret = atbm_reg_write_16(hw_priv, ATBM_HIFREG_CONTROL_REG_ID, val16 | ATBM_HIFREG_CONT_WUP_BIT);
		if (ret < 0) {
			atbm_dbg(ATBM_APOLLO_DBG_ERROR,
				"%s: set_wakeup: can't write " \
				"control register.\n", __func__);
			goto out;
		}


	out:
		return ret;

	unsubscribe:
		hw_priv->sbus_ops->irq_unsubscribe(hw_priv->sbus_priv);
		return ret;

}



