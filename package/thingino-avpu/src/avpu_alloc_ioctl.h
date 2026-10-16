#include <linux/device.h>
#include "avpu_ip.h"

int avpu_ioctl_get_dma_fd(struct device *dev, unsigned long arg);
int avpu_ioctl_get_dmabuf_dma_addr(struct device *dev, unsigned long arg);
int avpu_ioctl_get_dma_mmap(struct device *dev, struct avpu_codec_chan *chan,
			   unsigned long arg);

