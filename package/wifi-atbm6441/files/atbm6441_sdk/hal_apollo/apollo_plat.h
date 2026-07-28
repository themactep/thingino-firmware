/* *
 * Copyright (c) 2016, altobeam
 * Author:
 *
 *Based on apollo code
 * Copyright (C) ST-Ericsson SA 2011
 *
 * Author: Dmitry Tarnyagin <dmitry.tarnyagin@stericsson.com>
 * License terms: GNU General Public License (GPL) version 2
 */

#ifndef ATBM_APOLLO_PLAT_H_INCLUDED
#define ATBM_APOLLO_PLAT_H_INCLUDED

/*
*********************************************************
*
*PLATFORM_XUNWEI: based on linux3.0
*
*PLATFORM_SUN6I: based on linux3.3
*
*PLATFORM_FRIENDLY:based on linux3.086
*
*********************************************************
*/
#define PLATFORM_XUNWEI				(1)
#define PLATFORM_SUN6I  			(2)
#define PLATFORM_FRIENDLY			(3)
#define PLATFORM_SUN6I_64			(4)	
#define PLATFORM_CDLINUX			(12)
#define PLATFORM_AMLOGIC_S805		(13)	
#define PLATFORM_AMLOGIC_905		(8)	
#define PLATFORM_ANKAI_RTOS         (20)
#define PLATFORM_INGENIC_T40             (22)
#define PLATFORM_INGENIC_T41             (23)

#ifndef  ATBM_WIFI_PLATFORM
#define ATBM_WIFI_PLATFORM			PLATFORM_XUNWEI
#endif

#define APOLLO_1505  0
#define APOLLO_1601  1
#define APOLLO_1606  0
#define APOLLO_C     2
#define APOLLO_D     3
#define APOLLO_E     4
#define APOLLO_F     5
#define ATHENA_B     6
#define ATHENA_LITE  7
#define ATHENA_LITE_ECO  8
#define ARES_A  	 9
#define ARES_B  	 10
#define HERA         11


#ifndef PROJ_TYPE
#define PROJ_TYPE  ATHENA_B
#endif

#define CRYSTAL_MODE 0
#define EXTERNAL_MODE 1
#ifndef DCXO_TYPE
#define DCXO_TYPE   CRYSTAL_MODE
#endif

#define DPLL_CLOCK_26M 0
#define DPLL_CLOCK_40M 1
#define DPLL_CLOCK_24M 2

#ifndef DPLL_CLOCK
#define DPLL_CLOCK DPLL_CLOCK_40M
#endif

#ifdef LINUX_OS
#include <linux/ioport.h>
#endif

struct atbm_platform_data {
	const char *mmc_id;
	const int irq_gpio;
	const int power_gpio;
	const int reset_gpio;
	int (*power_ctrl)(const struct atbm_platform_data *pdata,
			  bool enable);
	int (*clk_ctrl)(const struct atbm_platform_data *pdata,
			  bool enable);
	int (*insert_ctrl)(const struct atbm_platform_data *pdata,
			  bool enable);
};

/* Declaration only. Should be implemented in arch/xxx/mach-yyy */
struct atbm_platform_data *atbm_get_platform_data(void);



#endif /* ATBM_APOLLO_PLAT_H_INCLUDED */
