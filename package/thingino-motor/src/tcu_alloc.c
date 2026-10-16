#include <linux/module.h>
#include <linux/spinlock.h>
#include <linux/errno.h>
#include <linux/printk.h>
#include "tcu_alloc.h"

static DEFINE_SPINLOCK(tcu_lock);
static unsigned int tcu_max_channels = 8;
static unsigned long tcu_claim_bitmap; /* up to 32 channels */
static char tcu_owner_name[TCU_ALLOC_MAX_CHANNELS][32];

int tcu_alloc_set_max_channels(unsigned int n)
{
	unsigned long flags;
	if (n == 0 || n > TCU_ALLOC_MAX_CHANNELS)
		return -EINVAL;
	spin_lock_irqsave(&tcu_lock, flags);
	if (n > tcu_max_channels)
		tcu_max_channels = n; /* only grow; never shrink to avoid dropping claims */
	spin_unlock_irqrestore(&tcu_lock, flags);
	return 0;
}
EXPORT_SYMBOL_GPL(tcu_alloc_set_max_channels);

int tcu_alloc_claim(unsigned int ch, const char *owner)
{
	unsigned long flags;
	if (ch >= tcu_max_channels)
		return -EINVAL;
	spin_lock_irqsave(&tcu_lock, flags);
	if (tcu_claim_bitmap & (1UL << ch)) {
		const char *cur = tcu_owner_name[ch][0] ? tcu_owner_name[ch] : "unknown";
		spin_unlock_irqrestore(&tcu_lock, flags);
		pr_err("TCU: channel %u already claimed by %s, cannot assign to %s\n", ch, cur, owner ? owner : "unknown");
		return -EBUSY;
	}
	tcu_claim_bitmap |= (1UL << ch);
	if (owner)
		strlcpy(tcu_owner_name[ch], owner, sizeof(tcu_owner_name[ch]));
	else
		tcu_owner_name[ch][0] = '\0';
	spin_unlock_irqrestore(&tcu_lock, flags);
	pr_info("TCU: channel %u claimed by %s\n", ch, owner ? owner : "unknown");
	return 0;
}
EXPORT_SYMBOL_GPL(tcu_alloc_claim);

void tcu_alloc_release(unsigned int ch, const char *owner)
{
	unsigned long flags;
	if (ch >= tcu_max_channels)
		return;
	spin_lock_irqsave(&tcu_lock, flags);
	tcu_claim_bitmap &= ~(1UL << ch);
	tcu_owner_name[ch][0] = '\0';
	spin_unlock_irqrestore(&tcu_lock, flags);
	pr_info("TCU: channel %u released (by %s)\n", ch, owner ? owner : "unknown");
}
EXPORT_SYMBOL_GPL(tcu_alloc_release);

bool tcu_alloc_is_claimed(unsigned int ch)
{
	bool ret;
	unsigned long flags;
	if (ch >= tcu_max_channels)
		return false;
	spin_lock_irqsave(&tcu_lock, flags);
	ret = tcu_claim_bitmap & (1UL << ch);
	spin_unlock_irqrestore(&tcu_lock, flags);
	return ret;
}
EXPORT_SYMBOL_GPL(tcu_alloc_is_claimed);

const char *tcu_alloc_owner(unsigned int ch)
{
	if (ch >= tcu_max_channels)
		return NULL;
	return tcu_owner_name[ch][0] ? tcu_owner_name[ch] : NULL;
}
EXPORT_SYMBOL_GPL(tcu_alloc_owner);

MODULE_DESCRIPTION("Ingenic TCU channel ownership registry");
MODULE_AUTHOR("Augment Agent");
MODULE_LICENSE("GPL v2");

