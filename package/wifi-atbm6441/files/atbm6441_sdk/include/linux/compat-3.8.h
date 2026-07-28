#ifndef LINUX_3_8_COMPAT_H
#define LINUX_3_8_COMPAT_H

#include <linux/version.h>
//#include <arch/arm/mach-exynos/include/mach/gpio.h>
#if (LINUX_VERSION_CODE < KERNEL_VERSION(3,8,0))
#define led_brightness_set led_set_brightness 
#if 0
/**
 * struct genl_info - receiving information
 * @snd_seq: sending sequence number
 * @snd_portid: netlink portid of sender
 * @nlhdr: netlink message header
 * @genlhdr: generic netlink message header
 * @userhdr: user specific header
 * @attrs: netlink attributes
 * @_net: network namespace
 * @user_ptr: user pointers
 */
#include <net/genetlink.h>
//#define genl_info atbm_genl_info
struct atbm_genl_info{
	struct genl_info *info;
        u32                     snd_seq;
        u32                     snd_portid;
        struct nlmsghdr *       nlhdr;
        struct genlmsghdr *     genlhdr;
        void *                  userhdr;
        struct nlattr **        attrs;
#ifdef CONFIG_NET_NS
        struct net *            _net;
#endif
        void *                  user_ptr[2];
};
#define genl_info atbm_genl_info
//#include <net/genetlink.h>

#endif
#endif /* LINUX_3_8_COMPAT_H */
#endif
