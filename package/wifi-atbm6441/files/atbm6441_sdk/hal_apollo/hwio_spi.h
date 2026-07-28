
#define HW_DOWN_FW
#define DOWNLOAD_BLOCK_SIZE		(50)


#ifndef ATBM_APOLLO_HWIO_SPI_H_INCLUDED
#define ATBM_APOLLO_HWIO_SPI_H_INCLUDED
#include "apollo_plat.h"

#define ALTOBEAM_WIFI_HDR_FLAG  (0x34353677)
#if (PROJ_TYPE>=ARES_A)
#define DOWNLOAD_ITCM_ADDR		(0x00010000)
#else
#define DOWNLOAD_ITCM_ADDR		(0x00000000)
#endif 
#define DOWNLOAD_ITCM_SIZE		(128*1024)
#define DOWNLOAD_DTCM_ADDR		(0x00800000)
#define DOWNLOAD_DTCM_SIZE		(48*1024)



#define SYS_BASE_ADDR_SILICON		(0)
#define PAC_BASE_ADDRESS_SILICON	(SYS_BASE_ADDR_SILICON + 0x09000000)
#define PAC_SHARED_MEMORY_SILICON	(PAC_BASE_ADDRESS_SILICON)

#define SPI_READ_BLOCK_SIZE	(32 *4 )
#define SPI_WRITE_BLOCK_SIZE	(264)

#define SPI_CHANNEL_FLAG 					BIT(0)
#define SPI_RDY_IRQ							BIT(1)
#define SPI_HW_SW_RDY						BIT(2)
#define SPI_RX_DATA_LENGTH(status)			((status >> 3) & 0x1fff) // bit [15:3]
#define SPI_STATUS_READY							BIT(16)
#define SPI_OVERRUN							BIT(17)
#define SPI_UNDERRUN						BIT(18)


int atbm_read_data(struct atbm_common *priv,  void *buf, u32 buf_len);
int atbm_write_data(struct atbm_common *priv,  const void *buf, u32 buf_len);
int atbm_read_status(struct atbm_common *priv, u32 *status);
int atbm_read_status_ready(struct atbm_common *priv, u32 *ready);
int atbm_update_status_channelflag(struct atbm_common *priv);
int atbm_read_status_channelflag(struct atbm_common *priv, u32 *channelflag);
int atbm_direct_write_reg_32(struct atbm_common *hw_priv, u32 addr, u32 val);
int atbm_direct_read_reg_32(struct atbm_common *hw_priv, u32 addr, u32 *val);

int atbm_fw_write(struct atbm_common *priv, u32 addr, const void *buf,
                        u32 buf_len);
#endif //ATBM_APOLLO_HWIO_SPI_H_INCLUDED
