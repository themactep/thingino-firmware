#pragma once

#define AL_CMD_UNBLOCK_CHANNEL _IO('q', 1)

#define AL_CMD_IP_WRITE_REG        _IOWR('q', 10, struct avpu_reg)
#define AL_CMD_IP_READ_REG         _IOWR('q', 11, struct avpu_reg)
#define AL_CMD_IP_WAIT_IRQ         _IOWR('q', 12, int)
#define GET_DMA_MMAP      _IOWR('q', 26, struct avpu_dma_info)
#define GET_DMA_FD        _IOWR('q', 13, struct avpu_dma_info)
#define GET_DMA_PHY       _IOWR('q', 18, struct avpu_dma_info)
#define JZ_CMD_FLUSH_CACHE			_IOWR('q', 14, int)

struct avpu_reg {
	unsigned int id;
	unsigned int value;
};

struct avpu_dma_info {
	__u32 fd;
	__u32 size;
	__u32 phy_addr;
};
