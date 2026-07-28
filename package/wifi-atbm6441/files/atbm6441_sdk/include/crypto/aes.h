#ifndef _COMPAT_CRYPTO_AES_H
#define _COMPAT_CRYPTO_AES_H

#include <linux/version.h>

#if (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,24))
#include_next <crypto/aes.h>
#else

#define AES_MIN_KEY_SIZE	16
#define AES_MAX_KEY_SIZE	32
#define AES_KEYSIZE_128		16
#define AES_KEYSIZE_192		24
#define AES_KEYSIZE_256		32
#define AES_BLOCK_SIZE		16
#define AES_MAX_KEYLENGTH	(15 * 16)
#define AES_MAX_KEYLENGTH_U32	(AES_MAX_KEYLENGTH / sizeof(u32))

#endif /* (LINUX_VERSION_CODE > KERNEL_VERSION(2,6,24)) */

#endif
