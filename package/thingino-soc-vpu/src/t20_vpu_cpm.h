/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __T20_VPU_CPM_H__
#define __T20_VPU_CPM_H__

#include <linux/io.h>

#define T20_CPM_IOBASE		0x10000000
#define T20_CPM_CLKGR1		0x28
#define T20_CPM_OPCR		0x24
#define T20_CPM_VPUCDR		0x30
#define T20_CPM_SRBC		0xc4

#define T20_OPCR_IDLE		BIT(31)

#define T20_CPM_VPU_SR(id)	(31 - 3 * (id))
#define T20_CPM_VPU_STP(id)	(30 - 3 * (id))
#define T20_CPM_VPU_ACK(id)	(29 - 3 * (id))

extern void __iomem *t20_cpm_base;

static inline u32 t20_cpm_inl(u32 off)
{
	return readl(t20_cpm_base + off);
}

static inline void t20_cpm_outl(u32 val, u32 off)
{
	writel(val, t20_cpm_base + off);
}

static inline void t20_cpm_set_bit(u32 bit, u32 off)
{
	t20_cpm_outl(t20_cpm_inl(off) | BIT(bit), off);
}

static inline void t20_cpm_clear_bit(u32 bit, u32 off)
{
	t20_cpm_outl(t20_cpm_inl(off) & ~BIT(bit), off);
}

#endif
