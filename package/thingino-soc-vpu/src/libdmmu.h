/* SPDX-License-Identifier: GPL-2.0 */
#ifndef __T20_LIBDMMU_H__
#define __T20_LIBDMMU_H__

struct device;

unsigned long dmmu_map(struct device *dev, unsigned long vaddr,
		       unsigned long len);
int dmmu_unmap(struct device *dev, unsigned long vaddr, int len);
int dmmu_unmap_all(struct device *dev);
void dmmu_dump_vaddr(unsigned long vaddr);

#endif
