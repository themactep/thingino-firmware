#include "avpu_alloc_ioctl.h"
#include "avpu_alloc.h"

#include <linux/uaccess.h>
#include "avpu_dmabuf.h"

int avpu_ioctl_get_dma_fd(struct device *dev, unsigned long arg)
{
	struct avpu_dma_info info;
	int err;

	if (copy_from_user(&info, (struct avpu_dma_info *)arg, sizeof(info)))
		return -EFAULT;

	err = avpu_allocate_dmabuf(dev, info.size, &info.fd);
	if (err)
		return err;

	err = avpu_dmabuf_get_address(dev, info.fd, &info.phy_addr);
	if (err)
		return err;

	if (copy_to_user((void *)arg, &info, sizeof(info)))
		return -EFAULT;

	return 0;
}

int add_buffer_to_list(struct avpu_codec_chan *chan, struct avpu_dma_buffer *buf)
{
	struct avpu_dma_buf_mmap *buf_mmap = kmalloc(sizeof(*buf_mmap), GFP_KERNEL);

	if (!buf_mmap)
		return -1;
	buf_mmap->buf = buf;
	spin_lock(&chan->lock);
	list_add_tail(&buf_mmap->list, &chan->mem);
	buf_mmap->buf_id = chan->num_bufs++;
	spin_unlock(&chan->lock);
	return buf_mmap->buf_id;
}

int avpu_ioctl_get_dma_mmap(struct device *dev, struct avpu_codec_chan *chan,
			   unsigned long arg)
{
	struct avpu_dma_info info;
	struct avpu_dma_buffer *buf = NULL;

	if (copy_from_user(&info, (struct avpu_dma_info *)arg, sizeof(info)))
		return -EFAULT;

	buf = avpu_alloc_dma(dev, info.size);

	if (!buf) {
		dev_err(dev, "Can't alloc DMA buffer\n");
		return -ENOMEM;
	}

	info.fd = add_buffer_to_list(chan, buf);
	if (info.fd == -1)
		return -ENOMEM;
	/* offset for mmap needs to be a multiple of page size */
	info.fd = info.fd << PAGE_SHIFT;

	info.phy_addr = (__u32)buf->dma_handle;

	pr_info("allocated buffer cpu: %p, phy:%d, offset:%d\n", buf->cpu_handle,
		info.phy_addr, info.fd);

	if (copy_to_user((void *)arg, &info, sizeof(info)))
		return -EFAULT;

	return 0;
}

int avpu_ioctl_get_dmabuf_dma_addr(struct device *dev, unsigned long arg)
{
	struct avpu_dma_info info;
	int err;

	if (copy_from_user(&info, (struct avpu_dma_info *)arg, sizeof(info)))
		return -EFAULT;

	err = avpu_dmabuf_get_address(dev, info.fd, &info.phy_addr);
	if (err)
		return err;

	if (copy_to_user((void *)arg, &info, sizeof(info)))
		return -EFAULT;

	return 0;
}
