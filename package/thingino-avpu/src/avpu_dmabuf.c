#include "avpu_compat.h"
#include "avpu_dmabuf.h"

#include <linux/uaccess.h>
#include <linux/dma-buf.h>
#include <linux/version.h>
#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/slab.h>
#include <linux/anon_inodes.h>

MODULE_LICENSE("GPL v2");
MODULE_AUTHOR("Kevin Grandemange");
MODULE_AUTHOR("Sebastien Alaiwan");
MODULE_AUTHOR("Antoine Gruzelle");
MODULE_DESCRIPTION("JZ Common");

struct avpu_dmabuf_priv {
	struct avpu_dma_buffer *buffer;

	/* DMABUF related */
	struct device *dev;
	struct sg_table *sgt_base;
	enum dma_data_direction dma_dir;

};

struct avpu_dmabuf_attachment {
	struct sg_table sgt;
	enum dma_data_direction dma_dir;
};

#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0)
/* device argument was removed */
static int avpu_dmabuf_attach(struct dma_buf *dbuf, struct dma_buf_attachment *dbuf_attach)
#else
static int avpu_dmabuf_attach(struct dma_buf *dbuf, struct device* dev, struct dma_buf_attachment *dbuf_attach)
#endif
{
	struct avpu_dmabuf_priv *dinfo = dbuf->priv;

	struct avpu_dmabuf_attachment *attach;

	struct scatterlist *rd, *wr;
	struct sg_table *sgt;
	int ret, i;

	attach = kzalloc(sizeof(*attach), GFP_KERNEL);
	if (!attach)
		return -ENOMEM;

	sgt = &attach->sgt;

	ret = sg_alloc_table(sgt, dinfo->sgt_base->orig_nents, GFP_KERNEL);
	if (ret) {
		kfree(attach);
		return -ENOMEM;
	}

	rd = dinfo->sgt_base->sgl;
	wr = sgt->sgl;

	for (i = 0; i < sgt->orig_nents; ++i) {
		sg_set_page(wr, sg_page(rd), rd->length, rd->offset);
		rd = sg_next(rd);
		wr = sg_next(wr);
	}

	attach->dma_dir = DMA_NONE;

	dbuf_attach->priv = attach;

	return 0;
}

#ifndef CONFIG_VIDEO_V4L2
__weak int is_dma_buf_file(struct file *);

struct dma_buf_list {
	struct list_head head;
	struct mutex lock;
};

static struct dma_buf_list db_list;

__weak int dma_buf_release(struct inode *inode, struct file *file)
{
	struct dma_buf *dmabuf;

	if (!is_dma_buf_file(file))
		return -EINVAL;

	dmabuf = file->private_data;

	BUG_ON(dmabuf->vmapping_counter);

	dmabuf->ops->release(dmabuf);

	mutex_lock(&db_list.lock);
	list_del(&dmabuf->list_node);
	mutex_unlock(&db_list.lock);

	kfree(dmabuf);
	return 0;
}

__weak int dma_buf_mmap_internal(struct file *file, struct vm_area_struct *vma)
{
	struct dma_buf *dmabuf;

	if (!is_dma_buf_file(file))
		return -EINVAL;

	dmabuf = file->private_data;

	/* check for overflowing the buffer's size */
	if (vma->vm_pgoff + ((vma->vm_end - vma->vm_start) >> PAGE_SHIFT) >
	    dmabuf->size >> PAGE_SHIFT)
		return -EINVAL;

	return dmabuf->ops->mmap(dmabuf, vma);
}

static const struct file_operations dma_buf_fops = {
	.release	= dma_buf_release,
	.mmap		= dma_buf_mmap_internal,
};

/*
 * is_dma_buf_file - Check if struct file* is associated with dma_buf
 */
__weak int is_dma_buf_file(struct file *file)
{
	return file->f_op == &dma_buf_fops;
}

/**
 * dma_buf_export_named - Creates a new dma_buf, and associates an anon file
 * with this buffer, so it can be exported.
 * Also connect the allocator specific data and ops to the buffer.
 * Additionally, provide a name string for exporter; useful in debugging.
 *
 * @priv:	[in]	Attach private data of allocator to this buffer
 * @ops:	[in]	Attach allocator-defined dma buf ops to the new buffer.
 * @size:	[in]	Size of the buffer
 * @flags:	[in]	mode flags for the file.
 * @exp_name:	[in]	name of the exporting module - useful for debugging.
 *
 * Returns, on success, a newly created dma_buf object, which wraps the
 * supplied private data and operations for dma_buf_ops. On either missing
 * ops, or error in allocating struct dma_buf, will return negative error.
 *
 */
__weak struct dma_buf *dma_buf_export_named(void *priv, const struct dma_buf_ops *ops,
				size_t size, int flags, const char *exp_name)
{
	struct dma_buf *dmabuf;
	struct file *file;

	if (WARN_ON(!priv || !ops
			  || !ops->map_dma_buf
			  || !ops->unmap_dma_buf
			  || !ops->release
			  || !ops->kmap_atomic
			  || !ops->kmap
			  || !ops->mmap)) {
		return ERR_PTR(-EINVAL);
	}

	dmabuf = kzalloc(sizeof(struct dma_buf), GFP_KERNEL);
	if (dmabuf == NULL)
		return ERR_PTR(-ENOMEM);

	dmabuf->priv = priv;
	dmabuf->ops = ops;
	dmabuf->size = size;
	dmabuf->exp_name = exp_name;

	file = anon_inode_getfile("dmabuf", &dma_buf_fops, dmabuf, flags);

	dmabuf->file = file;

	mutex_init(&dmabuf->lock);
	INIT_LIST_HEAD(&dmabuf->attachments);

	mutex_lock(&db_list.lock);
	list_add(&dmabuf->list_node, &db_list.head);
	mutex_unlock(&db_list.lock);

	return dmabuf;
}

__weak int dma_buf_fd(struct dma_buf *dmabuf, int flags)
{
	int fd;

	if (!dmabuf || !dmabuf->file)
		return -EINVAL;

	fd = get_unused_fd_flags(flags);
	if (fd < 0)
		return fd;

	fd_install(fd, dmabuf->file);

	return fd;
}

__weak struct dma_buf *dma_buf_get(int fd)
{
	struct file *file;

	file = fget(fd);

	if (!file)
		return ERR_PTR(-EBADF);

	if (!is_dma_buf_file(file)) {
		fput(file);
		return ERR_PTR(-EINVAL);
	}

	return file->private_data;
}

__weak void dma_buf_put(struct dma_buf *dmabuf)
{
	if (WARN_ON(!dmabuf || !dmabuf->file))
		return;

	fput(dmabuf->file);
}

/**
 * dma_buf_attach - Add the device to dma_buf's attachments list; optionally,
 * calls attach() of dma_buf_ops to allow device-specific attach functionality
 * @dmabuf:	[in]	buffer to attach device to.
 * @dev:	[in]	device to be attached.
 *
 * Returns struct dma_buf_attachment * for this attachment; may return negative
 * error codes.
 *
 */
__weak struct dma_buf_attachment *dma_buf_attach(struct dma_buf *dmabuf,
					  struct device *dev)
{
	struct dma_buf_attachment *attach;
	int ret;

	if (WARN_ON(!dmabuf || !dev))
		return ERR_PTR(-EINVAL);

	attach = kzalloc(sizeof(struct dma_buf_attachment), GFP_KERNEL);
	if (attach == NULL)
		return ERR_PTR(-ENOMEM);

	attach->dev = dev;
	attach->dmabuf = dmabuf;

	mutex_lock(&dmabuf->lock);

	if (dmabuf->ops->attach) {
		ret = dmabuf->ops->attach(dmabuf, dev, attach);
		if (ret)
			goto err_attach;
	}
	list_add(&attach->node, &dmabuf->attachments);

	mutex_unlock(&dmabuf->lock);
	return attach;

err_attach:
	kfree(attach);
	mutex_unlock(&dmabuf->lock);
	return ERR_PTR(ret);
}

__weak void dma_buf_detach(struct dma_buf *dmabuf, struct dma_buf_attachment *attach)
{
	if (WARN_ON(!dmabuf || !attach))
		return;

	mutex_lock(&dmabuf->lock);
	list_del(&attach->node);
	if (dmabuf->ops->detach)
		dmabuf->ops->detach(dmabuf, attach);

	mutex_unlock(&dmabuf->lock);
	kfree(attach);
}

/**
 * dma_buf_map_attachment - Returns the scatterlist table of the attachment;
 * mapped into _device_ address space. Is a wrapper for map_dma_buf() of the
 * dma_buf_ops.
 * @attach:	[in]	attachment whose scatterlist is to be returned
 * @direction:	[in]	direction of DMA transfer
 *
 * Returns sg_table containing the scatterlist to be returned; may return NULL
 * or ERR_PTR.
 *
 */
__weak struct sg_table *dma_buf_map_attachment(struct dma_buf_attachment *attach,
					enum dma_data_direction direction)
{
	struct sg_table *sg_table = ERR_PTR(-EINVAL);

	might_sleep();

	if (WARN_ON(!attach || !attach->dmabuf))
		return ERR_PTR(-EINVAL);

	sg_table = attach->dmabuf->ops->map_dma_buf(attach, direction);

	return sg_table;
}

/**
 * dma_buf_unmap_attachment - unmaps and decreases usecount of the buffer;might
 * deallocate the scatterlist associated. Is a wrapper for unmap_dma_buf() of
 * dma_buf_ops.
 * @attach:	[in]	attachment to unmap buffer from
 * @sg_table:	[in]	scatterlist info of the buffer to unmap
 * @direction:  [in]    direction of DMA transfer
 *
 */
__weak void dma_buf_unmap_attachment(struct dma_buf_attachment *attach,
				struct sg_table *sg_table,
				enum dma_data_direction direction)
{
	might_sleep();

	if (WARN_ON(!attach || !attach->dmabuf || !sg_table))
		return;

	attach->dmabuf->ops->unmap_dma_buf(attach, sg_table,
						direction);
}
#endif

static void avpu_dmabuf_detach(struct dma_buf *dbuf,
			      struct dma_buf_attachment *db_attach)
{
	struct avpu_dmabuf_attachment *attach = db_attach->priv;
	struct sg_table *sgt;

	if (!attach)
		return;

	sgt = &attach->sgt;

	/* release the scatterlist cache */
	if (attach->dma_dir != DMA_NONE)
		dma_unmap_sg(db_attach->dev, sgt->sgl, sgt->orig_nents,
			     attach->dma_dir);

	sg_free_table(sgt);
	kfree(attach);
	db_attach->priv = NULL;
}

static struct sg_table *avpu_dmabuf_map(struct dma_buf_attachment *db_attach,
				       enum dma_data_direction dma_dir)
{
	struct avpu_dmabuf_attachment *attach = db_attach->priv;
	struct sg_table *sgt;
	struct mutex *lock = &db_attach->dmabuf->lock;

	mutex_lock(lock);

	sgt = &attach->sgt;

	if (attach->dma_dir == dma_dir) {
		mutex_unlock(lock);
		return sgt;
	}

	if (attach->dma_dir != DMA_NONE) {
		dma_unmap_sg(db_attach->dev, sgt->sgl, sgt->orig_nents,
			     attach->dma_dir);
		attach->dma_dir = DMA_NONE;
	}

	sgt->nents = dma_map_sg(db_attach->dev, sgt->sgl, sgt->orig_nents,
				dma_dir);

	if (!sgt->nents) {
		pr_err("failed to map scatterlist\n");
		mutex_unlock(lock);
		return ERR_PTR(-EIO);
	}

	attach->dma_dir = dma_dir;

	mutex_unlock(lock);

	return sgt;
}

static void avpu_dmabuf_unmap(struct dma_buf_attachment *at,
			     struct sg_table *sg, enum dma_data_direction dir)
{
}

static int avpu_dmabuf_mmap(struct dma_buf *buf, struct vm_area_struct *vma)
{
	struct avpu_dmabuf_priv *dinfo = buf->priv;
	unsigned long start = vma->vm_start;
	unsigned long vsize = vma->vm_end - start;
	struct avpu_dma_buffer *buffer = dinfo->buffer;
	int ret;

	if (!dinfo) {
		pr_err("No buffer to map\n");
		return -EINVAL;
	}

	vma->vm_pgoff = 0;

	ret = dma_mmap_coherent(dinfo->dev, vma, buffer->cpu_handle,
				buffer->dma_handle, vsize);

	if (ret < 0) {
		pr_err("Remapping memory failed, error: %d\n", ret);
		return ret;
	}

	vma->vm_flags |= VM_DONTEXPAND | VM_DONTDUMP;

	return 0;
}

static void avpu_dmabuf_release(struct dma_buf *buf)
{
	struct avpu_dmabuf_priv *dinfo = buf->priv;
	struct avpu_dma_buffer *buffer = dinfo->buffer;

	if (dinfo->sgt_base) {
		sg_free_table(dinfo->sgt_base);
		kfree(dinfo->sgt_base);
	}


	dma_free_coherent(dinfo->dev, buffer->size, buffer->cpu_handle,
			  buffer->dma_handle);

	put_device(dinfo->dev);
	kzfree(buffer);
	kfree(dinfo);
}

static void *avpu_dmabuf_kmap(struct dma_buf *dmabuf, unsigned long page_num)
{
	struct avpu_dmabuf_priv *dinfo = dmabuf->priv;
	void *vaddr = dinfo->buffer->cpu_handle;

	return vaddr + page_num * PAGE_SIZE;
}

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
static int avpu_dmabuf_vmap(struct dma_buf *dbuf, struct dma_buf_map *map)
{
	struct avpu_dmabuf_priv *dinfo = dbuf->priv;

	dma_buf_map_set_vaddr(map, dinfo->buffer->cpu_handle);
	return 0;
}
#else
static void *avpu_dmabuf_vmap(struct dma_buf *dbuf)
{
	struct avpu_dmabuf_priv *dinfo = dbuf->priv;
	void *vaddr = dinfo->buffer->cpu_handle;

	return vaddr;
}
#endif

static const struct dma_buf_ops avpu_dmabuf_ops = {
	.attach		= avpu_dmabuf_attach,
	.detach		= avpu_dmabuf_detach,
	.map_dma_buf	= avpu_dmabuf_map,
	.unmap_dma_buf	= avpu_dmabuf_unmap,
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
	/* kmap/kmap_atomic were dropped; vmap takes a dma_buf_map. */
	.vmap		= avpu_dmabuf_vmap,
	.mmap		= avpu_dmabuf_mmap,
#elif LINUX_VERSION_CODE >= KERNEL_VERSION(4, 12, 0)
/* the map_atomic interface was removed after 4.19 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 19, 0)
	.map_atomic	= avpu_dmabuf_kmap,
#endif
	.map		= avpu_dmabuf_kmap,
	.vmap		= avpu_dmabuf_vmap,
	.mmap		= avpu_dmabuf_mmap,
#else
	.kmap_atomic	= avpu_dmabuf_kmap,
	.kmap		= avpu_dmabuf_kmap,
	.vmap		= avpu_dmabuf_vmap,
	.mmap		= avpu_dmabuf_mmap,
#endif
	.release	= avpu_dmabuf_release,
};

#if defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_SOC_T40) || defined(CONFIG_SOC_T41) || LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
static void define_export_info(struct dma_buf_export_info *exp_info, int size, void *priv)
{
	exp_info->owner = THIS_MODULE;
	exp_info->exp_name = KBUILD_MODNAME;
	exp_info->ops = &avpu_dmabuf_ops;
	exp_info->flags = O_RDWR;
	exp_info->resv = NULL;
	exp_info->size = size;
	exp_info->priv = priv;
}
#endif

static struct sg_table *avpu_get_base_sgt(struct avpu_dmabuf_priv *dinfo)
{
	int ret;
	struct sg_table *sgt;
	struct avpu_dma_buffer *buf = dinfo->buffer;
	struct device *dev = dinfo->dev;

	sgt = kzalloc(sizeof(*sgt), GFP_KERNEL);
	if (!sgt)
		return NULL;

	ret = dma_get_sgtable(dev, sgt, buf->cpu_handle, buf->dma_handle,
			      buf->size);
	if (ret < 0) {
		kfree(sgt);
		return NULL;
	}

	return sgt;

}

static struct dma_buf *avpu_get_dmabuf(void *dma_info_priv)
{
	struct dma_buf *dbuf;
	struct avpu_dmabuf_priv *dinfo = dma_info_priv;
	struct avpu_dma_buffer *buf = dinfo->buffer;
/*
 * The dma_buf_export() signature changed to take a struct dma_buf_export_info
 * on 4.4.94. 3.10.14 uses the new signature only for T40/T41; T31/C100 still
 * use the legacy (priv, ops, size, flags) form.
 */
#if defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_SOC_T40) || defined(CONFIG_SOC_T41) || LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
	struct dma_buf_export_info exp_info;
#endif

	if (!dinfo->sgt_base)
		dinfo->sgt_base = avpu_get_base_sgt(dinfo);

	if (WARN_ON(!dinfo->sgt_base))
		return NULL;

#if defined(CONFIG_KERNEL_4_4_94) || defined(CONFIG_SOC_T40) || defined(CONFIG_SOC_T41) || LINUX_VERSION_CODE >= KERNEL_VERSION(5, 11, 0)
	define_export_info(&exp_info, buf->size, (void *)dinfo);
	dbuf = dma_buf_export(&exp_info);
	if (IS_ERR(dbuf)) {
		pr_err("couldn't export dma buf\n");
		return NULL;
	}
#else
	dbuf = dma_buf_export((void *)dinfo, &avpu_dmabuf_ops, buf->size, O_RDWR);
	if (IS_ERR(buf)) {
		pr_err("couldn't export dma buf\n");
		return NULL;
	}
#endif
	return dbuf;
}

static void *avpu_dmabuf_wrap(struct device *dev, unsigned long size,
			     struct avpu_dma_buffer *buffer)
{
	struct avpu_dmabuf_priv *dinfo;
	struct dma_buf *dbuf;

	dinfo = kzalloc(sizeof(*dinfo), GFP_KERNEL);
	if (!dinfo)
		return ERR_PTR(-ENOMEM);

	dinfo->dev = get_device(dev);
	dinfo->buffer = buffer;
	dinfo->dma_dir = DMA_BIDIRECTIONAL;
	dinfo->sgt_base = avpu_get_base_sgt(dinfo);

	dbuf = avpu_get_dmabuf(dinfo);
	if (IS_ERR_OR_NULL(dbuf))
		return ERR_PTR(-EINVAL);

	return dbuf;
}

int avpu_create_dmabuf_fd(struct device *dev, unsigned long size,
			 struct avpu_dma_buffer *buffer)
{
	struct dma_buf *dbuf = avpu_dmabuf_wrap(dev, size, buffer);

	if (IS_ERR(dbuf))
		return PTR_ERR(dbuf);
	return dma_buf_fd(dbuf, O_RDWR);
}

int avpu_allocate_dmabuf(struct device *dev, int size, u32 *fd)
{
	struct avpu_dma_buffer *buffer;

	buffer = avpu_alloc_dma(dev, size);
	if (!buffer) {
		dev_err(dev, "Can't alloc DMA buffer\n");
		return -ENOMEM;
	}

	*fd = avpu_create_dmabuf_fd(dev, size, buffer);
	return 0;
}

int avpu_dmabuf_get_address(struct device *dev, u32 fd, u32 *bus_address)
{
	struct dma_buf *dbuf;
	struct dma_buf_attachment *attach;
	struct sg_table *sgt;
	int err = 0;

	dbuf = dma_buf_get(fd);
	if (IS_ERR(dbuf))
		return -EINVAL;
	attach = dma_buf_attach(dbuf, dev);
	if (IS_ERR(attach)) {
		err = -EINVAL;
		goto fail_attach;
	}
	sgt = dma_buf_map_attachment(attach, DMA_BIDIRECTIONAL);
	if (IS_ERR(sgt)) {
		err = -EINVAL;
		goto fail_map;
	}

	*bus_address = sg_dma_address(sgt->sgl);

	dma_buf_unmap_attachment(attach, sgt, DMA_BIDIRECTIONAL);
fail_map:
	dma_buf_detach(dbuf, attach);
fail_attach:
	dma_buf_put(dbuf);
	return err;
}

