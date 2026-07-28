/*
 * Firmware API for mac80211 altobeam APOLLO drivers
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

#ifndef FWIO_H_INCLUDED
#define FWIO_H_INCLUDED

#ifndef CONFIG_FW_NAME
#if ((ATBM_WIFI_PLATFORM == 13/*PLATFORM_AMLOGIC_S805*/) || (ATBM_WIFI_PLATFORM == 8))
#define FIRMWARE_DEFAULT_PATH	"../wifi/atbm/fw.bin"
#else // PLATFORM_AMLOGIC_S805
#define FIRMWARE_DEFAULT_PATH	"fw.bin"
#endif //PLATFORM_AMLOGIC_S805
#else 
#define FIRMWARE_DEFAULT_PATH CONFIG_FW_NAME 
#endif
#define SDD_FILE_DEFAULT_PATH	("sdd.bin")

#define ATBM_APOLLO_REV_1601	(1601)

struct atbm_common;


int atbm_get_hw_type(u32 config_reg_val, int *major_revision);

int atbm_load_firmware(struct atbm_common *hw_priv);
void atbm_release_firmware(void);
int atbm_init_firmware(void);
#endif
