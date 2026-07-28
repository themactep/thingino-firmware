/*
 * Low-level API for mac80211 altobeam apollo wifi drivers
 *
 * Copyright (c) 2016, altobeam
 *
 * Based on:
 * Copyright (c) 2010, stericsson
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

#ifndef ATBM_APOLLO_HWIO_H_INCLUDED
#define ATBM_APOLLO_HWIO_H_INCLUDED


/* extern */ struct atbm_common;
/* Hardware Type Definitions */
#define HIF_1601_FPGA		(0)
#define HIF_1601_CHIP		(1)


#define RATE_INDEX_B_1M 0
#define RATE_INDEX_B_2M 1
#define RATE_INDEX_B_11M 3
#define RATE_INDEX_A_6M 6
#define RATE_INDEX_A_9M 7
#define RATE_INDEX_A_12M 8
#define RATE_INDEX_A_24M 10
#define RATE_INDEX_A_36M 11
#define RATE_INDEX_A_54M 13
#define RATE_INDEX_N_6_5M 14
#define RATE_INDEX_N_13M 15
#define RATE_INDEX_N_26M 17
#define RATE_INDEX_N_39M 18
#define RATE_INDEX_N_52M 19
#define RATE_INDEX_N_65M 21

/* Download error code */
#define DOWNLOAD_PENDING		(0xFFFFFFFF)
#define DOWNLOAD_SUCCESS		(0)
#define DOWNLOAD_EXCEPTION		(1)
#define DOWNLOAD_ERR_MEM_1		(2)
#define DOWNLOAD_ERR_MEM_2		(3)
#define DOWNLOAD_ERR_SOFTWARE		(4)
#define DOWNLOAD_ERR_FILE_SIZE		(5)
#define DOWNLOAD_ERR_CHECKSUM		(6)
#define DOWNLOAD_ERR_OVERFLOW		(7)
#define DOWNLOAD_ERR_IMAGE		(8)
#define DOWNLOAD_ERR_HOST		(9)
#define DOWNLOAD_ERR_ABORT		(10)



#ifdef SDIO_BUS
#include "hwio_sdio.h"

#elif defined  SPI_BUS
#include "hwio_spi.h"

#else
#pragma message("BUS error. must select SDIO or SPI driver")

#endif 

int atbm_fw_write(struct atbm_common *priv, u32 addr, const void *buf,u32 buf_len);
int atbm_before_load_firmware(struct atbm_common *hw_priv);
int atbm_after_load_firmware(struct atbm_common *hw_priv);
void atbm_firmware_init_check(struct atbm_common *hw_priv);
int atbm_reset_lmc_cpu(struct atbm_common *hw_priv);
int atbm_reset_chip(struct atbm_common *hw_priv);

#ifndef atbm_module_muxlock
#define atbm_module_muxlock()
#endif

#ifndef atbm_module_muxunlock
#define atbm_module_muxunlock()
#endif
#endif //ATBM_APOLLO_HWIO_H_INCLUDED
