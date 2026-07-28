#ifndef LINUX_26_37_COMPAT_H
#define LINUX_26_37_COMPAT_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,37))

#include <linux/skbuff.h>
#include <linux/leds.h>

#define SDIO_CLASS_BT_AMP	0x09	/* Type-A Bluetooth AMP interface */

extern struct kobj_ns_type_operations net_ns_type_operations;

/**
 * skb_checksum_none_assert - make sure skb ip_summed is CHECKSUM_NONE
 * @skb: skb to check
 *
 * fresh skbs have their ip_summed set to CHECKSUM_NONE.
 * Instead of forcing ip_summed to CHECKSUM_NONE, we can
 * use this helper, to document places where we make this assertion.
 */
static inline void skb_checksum_none_assert(struct sk_buff *skb)
{
#ifdef DEBUG
	BUG_ON(skb->ip_summed != CHECKSUM_NONE);
#endif
}

#define pcmcia_enable_device(link)	pcmcia_request_configuration(link, &link->conf)

#include <net/genetlink.h>

struct compat_genl_info {
	struct genl_info *info;

	u32 snd_seq;
	u32 snd_pid;
	struct genlmsghdr *genlhdr;
	struct nlattr **attrs;
	void *user_ptr[2];
};
#define genl_info compat_genl_info

struct compat_genl_ops {
	struct genl_ops ops;

	u8 cmd;
	u8 internal_flags;
	unsigned int flags;
	const struct nla_policy *policy;

	int (*doit)(struct sk_buff *skb, struct genl_info *info);
	int (*dumpit)(struct sk_buff *skb, struct netlink_callback *cb);
	int (*done)(struct netlink_callback *cb);
};
#define genl_ops compat_genl_ops

struct compat_genl_family {
	struct genl_family family;

	struct list_head list;

	unsigned int id, hdrsize, version, maxattr;
	const char *name;
	bool netnsok;

	struct nlattr **attrbuf;

	int (*pre_doit)(struct genl_ops *ops, struct sk_buff *skb,
			struct genl_info *info);

	void (*post_doit)(struct genl_ops *ops, struct sk_buff *skb,
			  struct genl_info *info);
};

#define genl_family compat_genl_family

#define genl_register_family_with_ops compat_genl_register_family_with_ops

int genl_register_family_with_ops(struct genl_family *family,
				  struct genl_ops *ops, size_t n_ops);

#define genl_unregister_family compat_genl_unregister_family

int genl_unregister_family(struct genl_family *family);

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,32))
#define genl_info_net(_info) genl_info_net((_info)->info)
#endif

#define genlmsg_reply(_msg, _info) genlmsg_reply(_msg, (_info)->info)
#define genlmsg_put(_skb, _pid, _seq, _fam, _flags, _cmd) genlmsg_put(_skb, _pid, _seq, &(_fam)->family, _flags, _cmd)
#define genl_register_mc_group(_fam, _grp) genl_register_mc_group(&(_fam)->family, _grp)
#define genl_unregister_mc_group(_fam, _grp) genl_unregister_mc_group(&(_fam)->family, _grp)


extern void led_blink_set(struct led_classdev *led_cdev,
			  unsigned long *delay_on,
			  unsigned long *delay_off);

#define led_classdev_unregister compat_led_classdev_unregister
extern void compat_led_classdev_unregister(struct led_classdev *led_cdev);

#define led_brightness_set compat_led_brightness_set
extern void compat_led_brightness_set(struct led_classdev *led_cdev,
				      enum led_brightness brightness);

#define alloc_ordered_workqueue(name, flags) create_singlethread_workqueue(name)

#define netdev_refcnt_read(a) atomic_read(&a->refcnt)

extern void *vzalloc(unsigned long size);

#define rtnl_dereference(p)                                     \
        rcu_dereference_protected(p, lockdep_rtnl_is_held())

/**
 * RCU_INIT_POINTER() - initialize an RCU protected pointer
 *
 * Initialize an RCU-protected pointer in such a way to avoid RCU-lockdep
 * splats.
 */
#define RCU_INIT_POINTER(p, v) \
		p = (typeof(*v) __force __rcu *)(v)

static inline bool skb_has_frag_list(const struct sk_buff *skb)
{
	return skb_shinfo(skb)->frag_list != NULL;
}

#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,37)) */

#endif /* LINUX_26_37_COMPAT_H */
