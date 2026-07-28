#ifndef LINUX_3_2_COMPAT_H
#define LINUX_3_2_COMPAT_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,2,0))

#include <linux/skbuff.h>
#include <linux/dma-mapping.h>

#define PMSG_IS_AUTO(msg)	(((msg).event & PM_EVENT_AUTO) != 0)

/**
 * skb_frag_page - retrieve the page refered to by a paged fragment
 * @frag: the paged fragment
 *
 * Returns the &struct page associated with @frag.
 */
static inline struct page *skb_frag_page(const skb_frag_t *frag)
{
	return frag->page;
}

/**
 * skb_frag_dma_map - maps a paged fragment via the DMA API
 * @device: the device to map the fragment to
 * @frag: the paged fragment to map
 * @offset: the offset within the fragment (starting at the
 *          fragment's own offset)
 * @size: the number of bytes to map
 * @direction: the direction of the mapping (%PCI_DMA_*)
 *
 * Maps the page associated with @frag to @device.
 */
static inline dma_addr_t skb_frag_dma_map(struct device *dev,
					  const skb_frag_t *frag,
					  size_t offset, size_t size,
					  enum dma_data_direction dir)
{
	return dma_map_page(dev, skb_frag_page(frag),
			    frag->page_offset + offset, size, dir);
}

#define ETH_P_TDLS	0x890D          /* TDLS */

static inline unsigned int skb_frag_size(const skb_frag_t *frag)
{
	return frag->size;
}

static inline char *hex_byte_pack(char *buf, u8 byte)
{
	*buf++ = hex_asc_hi(byte);
	*buf++ = hex_asc_lo(byte);
	return buf;
}

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(3,2,0)) */

#endif /* LINUX_3_2_COMPAT_H */
