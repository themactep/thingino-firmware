#ifndef LINUX_26_35_COMPAT_H
#define LINUX_26_35_COMPAT_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,35))
#include <linux/etherdevice.h>
#include <net/sock.h>
#include <linux/types.h>
#include <linux/usb.h>

/* added on linux/kernel.h */
#define USHRT_MAX      ((u16)(~0U))
#define SHRT_MAX       ((s16)(USHRT_MAX>>1))
#define SHRT_MIN       ((s16)(-SHRT_MAX - 1))

#define  SDIO_BUS_ECSI		0x20	/* Enable continuous SPI interrupt */
#define  SDIO_BUS_SCSI		0x40	/* Support continuous SPI interrupt */

#define netdev_hw_addr dev_mc_list

static inline wait_queue_head_t *sk_sleep(struct sock *sk)
{
	return sk->sk_sleep;
}

#define sdio_writeb_readb(func, write_byte, addr, err_ret) sdio_readb(func, addr, err_ret)

int hex_to_bin(char ch);

extern loff_t noop_llseek(struct file *file, loff_t offset, int origin);

#define pm_qos_request(_qos) pm_qos_requirement(_qos)

static inline struct usb_host_endpoint *
usb_pipe_endpoint(struct usb_device *dev, unsigned int pipe)
{
	struct usb_host_endpoint **eps;
	eps = usb_pipein(pipe) ? dev->ep_in : dev->ep_out;
	return eps[usb_pipeendpoint(pipe)];
}

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,35)) */

#endif /* LINUX_26_35_COMPAT_H */
