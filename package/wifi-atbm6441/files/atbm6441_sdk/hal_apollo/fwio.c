/*
 * Firmware I/O code for mac80211 altobeam APOLLO drivers
 * *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 * Based on apollo code
 * Copyright (c) 2010, ST-Ericsson
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 *
 * Based on:
 * ST-Ericsson UMAC CW1200 driver which is
 * Copyright (c) 2010, ST-Ericsson
 * Author: Ajitpal Singh <ajitpal.singh@stericsson.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 */

#ifdef LINUX_OS
#include <linux/init.h>
#include <linux/vmalloc.h>
#include <linux/sched.h>
#include <linux/firmware.h>
#include <linux/module.h>
#include <linux/debugfs.h>
#endif

#include "apollo.h"
#include "fwio.h"
#include "hwio.h"
#include "sbus.h"
#include "bh.h"
#include "debug.h"

#include "dcxo_dpll.h"

#ifdef ATBM_USE_SAVED_FW
#pragma message("Suspend Save Firmware")
#endif
#ifdef CONFIG_USE_FW_H
#pragma message("Use Firmware.h")
#endif
static char *fw = FIRMWARE_DEFAULT_PATH;
module_param(fw, charp, 0644);
MODULE_PARM_DESC(fw, "Override platform_data firmware file");
#pragma message(FIRMWARE_DEFAULT_PATH)


struct firmware_headr {
	u32 flags; /*0x34353677*/
	u32 version;
	u32 iccm_len;
	u32 dccm_len;
	u32 reserve[3];
	u16 reserve2;
	u16 checksum;
};

struct firmware_altobeam {
	struct firmware_headr hdr;
	u8 *fw_iccm;
	u8 *fw_dccm;
};
static struct firmware_altobeam atbm_fw;

void atbm_release_firmware(void)
{
	atbm_printk_exit("atbm_release_firmware\n");
	if(atbm_fw.fw_dccm)
	{
		vfree(atbm_fw.fw_dccm);
		atbm_fw.fw_dccm = NULL;
	}
	if(atbm_fw.fw_iccm)
	{
		vfree(atbm_fw.fw_iccm);
		atbm_fw.fw_iccm = NULL;
	}
}
int atbm_init_firmware(void)
{
	atbm_printk_init("atbm_init_firmware\n");
	memset(&atbm_fw,0,sizeof(struct firmware_altobeam));
	return 0;
}

int atbm_set_firmare(struct firmware_altobeam *fw)
{
#ifdef ATBM_USE_SAVED_FW
	if(!fw || (!fw->fw_dccm&&!fw->fw_iccm))
	{
		atbm_printk_err(KERN_ERR "fw is err\n");
		return -1;
	}

	if(atbm_fw.fw_dccm || atbm_fw.fw_iccm)
	{
		atbm_printk_err("atbm_fw has been set\n");
		return -1;
	}
	memcpy(&atbm_fw.hdr,&fw->hdr,sizeof(struct firmware_headr));
	
	if(atbm_fw.hdr.iccm_len)
	{
		atbm_fw.fw_iccm = vmalloc(atbm_fw.hdr.iccm_len);
		atbm_printk_err("%s:fw_iccm(%p)\n",__func__,atbm_fw.fw_iccm);
		if(!atbm_fw.fw_iccm)
		{
			atbm_printk_err("alloc atbm_fw.fw_iccm err\n");
			goto err;
		}
		memcpy(atbm_fw.fw_iccm,fw->fw_iccm,atbm_fw.hdr.iccm_len);
	}

	if(atbm_fw.hdr.dccm_len)
	{
		atbm_fw.fw_dccm= vmalloc(atbm_fw.hdr.dccm_len);
		
		atbm_printk_err("%s:fw_dccm(%p)\n",__func__,atbm_fw.fw_dccm);
		if(!atbm_fw.fw_dccm)
		{
			atbm_printk_err("alloc atbm_fw.fw_dccm err\n");
			goto err;
		}
		memcpy(atbm_fw.fw_dccm,fw->fw_dccm,atbm_fw.hdr.dccm_len);
	}
	return 0;
err:
	if(atbm_fw.fw_iccm)
	{
		vfree(atbm_fw.fw_iccm);
		atbm_fw.fw_iccm = NULL;
	}

	if(atbm_fw.fw_dccm)
	{
		vfree(atbm_fw.fw_dccm);
		atbm_fw.fw_dccm = NULL;
	}
#endif //#ifndef USB_BUS
	return -1;
}

#define FW_IS_READY	((atbm_fw.fw_dccm != NULL) || (atbm_fw.fw_iccm != NULL))
int atbm_get_fw(struct firmware_altobeam *fw)
{
	if(!FW_IS_READY)
	{
		return -1;
	}

	memcpy(&fw->hdr,&atbm_fw.hdr,sizeof(struct firmware_headr));
	fw->fw_iccm = atbm_fw.fw_iccm;
	fw->fw_dccm = atbm_fw.fw_dccm;
	atbm_printk_always("%s:get fw\n",__func__);
	return 0;
}


int atbm_get_hw_type(u32 config_reg_val, int *major_revision)
{
	return HIF_1601_CHIP;
}

char * atbm_HwGetChipFw(struct atbm_common *priv)
{
	u32 chipver = 0;
	char * strHwChipFw;

	if(fw)
	{
		atbm_printk_always("%s, use module_param fw [%s]\n",__func__, fw );
	 	return fw;
	}

	atbm_direct_read_reg_32(priv,0x0acc017c,&chipver);
	chipver&=0x3f;
	switch(chipver)
	{
		case 0x0:	
			strHwChipFw = ("ApolloC0.bin");		
			break;
		case 0x1:	
			strHwChipFw = ("ApolloC0_TC.bin");	
			break;
		case 0x3:	
			strHwChipFw = ("ApolloC1_TC.bin");	
			break;
		case 0xc:	
			strHwChipFw = ("ApolloD.bin");		
			break;
		case 0xd:	
			strHwChipFw = ("ApolloD_TC.bin");	
			break;
		case 0x10:	
			strHwChipFw = ("ApolloE.bin");		
			break;
		case 0x20:	
			strHwChipFw = ("AthenaA.bin");		
			break;
		case 0x14:	
			strHwChipFw = ("ApolloF.bin");		
			break;
		case 0x15:	
			strHwChipFw = ("ApolloF_TC.bin");	
			break;
		case 0x24:	
			strHwChipFw = ("AthenaB.bin");		
			break;
		case 0x25:	
			strHwChipFw = ("AthenaBX.bin");		
			break;
		case 0x18:	
			strHwChipFw = ("Apollo_FM.bin");		
			break;
		default:
			strHwChipFw = FIRMWARE_DEFAULT_PATH;		
		break;
	}

	atbm_printk_always("%s, chipver=0x%x, use fw [%s]\n",__func__, chipver,strHwChipFw );

	return strHwChipFw;
}

//#define TEST_DCXO_CONFIG move to makefile
#ifndef CONFIG_USE_FW_H
#define USED_FW_FILE
#endif
#ifdef USED_FW_FILE
#else
#include "firmware.h"
#endif

int atbm_load_firmware(struct atbm_common *hw_priv)
{
	int ret;
#if (PROJ_TYPE==ARES_B)

	atbm_printk_init("atbm_before_load_firmware++\n");
	ret = atbm_before_load_firmware(hw_priv);
	if(ret <0)
		goto out;
	atbm_printk_init("atbm_start_load_firmware++\n");
	ret = atbm_start_load_firmware(hw_priv);
	if(ret <0)
		goto out;
#endif
	atbm_printk_init("atbm_after_load_firmware++\n");
	ret = atbm_after_load_firmware(hw_priv);
	if(ret <0){
		goto out;
	}
	ret =0;
out:
	return ret;

}

