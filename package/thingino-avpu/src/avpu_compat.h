#ifndef _AVPU_COMPAT_H
#define _AVPU_COMPAT_H

#include <linux/version.h>

/* APIs removed or renamed after 4.4, when the driver was written. */

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 0, 0)
#ifndef devm_ioremap_nocache
#define devm_ioremap_nocache(dev, offset, size) devm_ioremap((dev), (offset), (size))
#endif
#ifndef kzfree
#define kzfree(p) kfree_sensitive(p)
#endif
#endif

#endif /* _AVPU_COMPAT_H */
