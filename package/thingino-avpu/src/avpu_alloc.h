#ifndef _AL_ALLOC_H_
#define _AL_ALLOC_H_

#include <linux/device.h>

struct avpu_dma_buffer {
	u32 size;
	dma_addr_t dma_handle;
	void *cpu_handle;
};

struct avpu_dma_buffer *avpu_alloc_dma(struct device *dev, size_t size);
void avpu_free_dma(struct device *dev, struct avpu_dma_buffer *buf);

#endif /* _AL_ALLOC_H_ */
