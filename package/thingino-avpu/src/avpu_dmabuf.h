#include <linux/device.h>
#include "avpu_alloc.h"

struct avpu_buffer_info {
	u32 bus_address;
	u32 size;
};

int avpu_create_dmabuf_fd(struct device *dev, unsigned long size,
			 struct avpu_dma_buffer *buffer);
int avpu_allocate_dmabuf(struct device *dev, int size, u32 *fd);
int avpu_dmabuf_get_address(struct device *dev, u32 fd, u32 *bus_address);

