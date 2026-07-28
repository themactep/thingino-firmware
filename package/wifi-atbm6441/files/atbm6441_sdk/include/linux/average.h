#include <linux/version.h>

#if (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,37))
#include_next <linux/average.h>
#endif /* (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,37)) */
