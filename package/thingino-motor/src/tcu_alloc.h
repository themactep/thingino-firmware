#ifndef __TCU_ALLOC_H__
#define __TCU_ALLOC_H__

#include <linux/types.h>

/* Simple central registry for Ingenic TCU channel ownership.
 * First claimant wins; subsequent claimants get -EBUSY.
 */

#define TCU_ALLOC_MAX_CHANNELS 16

int tcu_alloc_set_max_channels(unsigned int n);
int tcu_alloc_claim(unsigned int ch, const char *owner);
void tcu_alloc_release(unsigned int ch, const char *owner);
bool tcu_alloc_is_claimed(unsigned int ch);
const char *tcu_alloc_owner(unsigned int ch);

#endif /* __TCU_ALLOC_H__ */

