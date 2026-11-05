#ifndef __JZ_T20_NCU__
#define __JZ_T20_NCU__

//#define CONFIG_FPGA_TEST
/* register */
#define NCU_START				0x0000
#define NCU_STATUS				0x0004

#define ncu_read(offset) __raw_readl((void __iomem *)0xb3090000 + offset)
#define ncu_write(offset, val) __raw_writel((val), (void __iomem *)0xb3090000 + offset)

/* 0x0000 */
#define NCU_START_BIT		1 << 0
#define NCU_RST			1 << 1

typedef struct{
  unsigned int addr;
  unsigned int val;
}ncu_reg_info_t;

#endif// __JZ_T20_NCU__
