#ifndef LINUX_26_23_COMPAT_H
#define LINUX_26_23_COMPAT_H

#include <linux/version.h>

/* Compat work for < 2.6.23 */
#if (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,23))

#include <linux/netdevice.h>
#include <linux/sched.h>
#include <linux/workqueue.h>
#include <linux/genetlink.h>
#include <net/sch_generic.h>

/*
 * Tell gcc if a function is cold. The compiler will assume any path
 * directly leading to the call is unlikely.
 */

#if !(__GNUC__ == 4 && __GNUC_MINOR__ < 3)
/* Mark functions as cold. gcc will assume any path leading to a call
 * to them will be unlikely.  This means a lot of manual unlikely()s
 * are unnecessary now for any paths leading to the usual suspects
 * like BUG(), printk(), panic() etc. [but let's keep them for now for
 * older compilers]
 *
 * Early snapshots of gcc 4.3 don't support this and we can't detect this
 * in the preprocessor, but we can live with this because they're unreleased.
 * Maketime probing would be overkill here.
 *
 * gcc also has a __attribute__((__hot__)) to move hot functions into
 * a special section, but I don't see any sense in this right now in
 * the kernel context */
#define __cold                  __attribute__((__cold__))
#endif /* gcc 4.3 check */

#ifndef __cold
#define __cold
#endif

/* Added as of 2.6.23 in include/linux/netdevice.h */
#define alloc_netdev_mq(sizeof_priv, name, setup, queue) \
	alloc_netdev(sizeof_priv, name, setup)
#define NETIF_F_MULTI_QUEUE 16384

/* Added as of 2.6.23 on include/linux/netdevice.h */
static inline int netif_is_multiqueue(const struct net_device *dev)
{
	return (!!(NETIF_F_MULTI_QUEUE & dev->features));
}

/* 2.6.23 fixed a bug in tcf_destroy_chain and the parameter changed */
static inline void tcf_destroy_chain_compat(struct tcf_proto **fl)
{
	struct tcf_proto *tp;

	while ((tp = *fl) != NULL) {
		*fl = tp->next;
		tp->ops->destroy(tp);
		module_put(tp->ops->owner);
		atbm_kfree(tp);
	}
}

/* dev_mc_list was replaced with dev_addr_list as of 2.6.23,
 * only new member added is da_synced. */
#define dev_addr_list	dev_mc_list
#define da_addr		dmi_addr
#define da_addrlen	dmi_addrlen
#define da_users	dmi_users
#define da_gusers	dmi_gusers

/* dev_set_promiscuity() was moved to __dev_set_promiscuity() on 2.6.23 and
 * dev_set_promiscuity() became a wrapper. */
#define __dev_set_promiscuity dev_set_promiscuity

/* Our own 2.6.22 port on compat.c */
extern void	dev_mc_unsync(struct net_device *to, struct net_device *from);
extern int	dev_mc_sync(struct net_device *to, struct net_device *from);

/* Our own 2.6.22 port on compat.c */
extern void	__dev_set_rx_mode(struct net_device *dev);

/* Simple to add this */
extern int cancel_delayed_work_sync(struct delayed_work *work);

#define cancel_delayed_work_sync cancel_rearming_delayed_work

#define debugfs_rename(a, b, c, d) 1

/* nl80211 requires multicast group support which is new and added on
 * 2.6.23. We can't add support for it for older kernels to support it
 * genl_family structure was changed. Lets just let through the
 * genl_register_mc_group call. This means no multicast group suppport */

#define genl_register_mc_group(a, b) 0

/**
 * struct genl_multicast_group - generic netlink multicast group
 * @name: name of the multicast group, names are per-family
 * @id: multicast group ID, assigned by the core, to use with
 * 	genlmsg_multicast().
 * @list: list entry for linking
 * @family: pointer to family, need not be set before registering
 */
struct genl_multicast_group
{
	struct genl_family      *family;        /* private */
	struct list_head        list;           /* private */
	char                    name[GENL_NAMSIZ];
	u32                     id;
};


/* Added as of 2.6.23 */
int pci_try_set_mwi(struct pci_dev *dev);

/* Added as of 2.6.23 */
#ifdef CONFIG_PM_SLEEP
/*
 * Tell the freezer that the current task should be frozen by it
 */
static inline void set_freezable(void)
{
	current->flags &= ~PF_NOFREEZE;
}

#else
static inline void set_freezable(void) {}
#endif /* CONFIG_PM_SLEEP */

#else
#define tcf_destroy_chain_compat tcf_destroy_chain
#endif /* (LINUX_VERSION_CODE < KERNEL_VERSION(2,6,23)) */

#endif /* LINUX_26_23_COMPAT_H */
