# Camera-local make defaults for T31 SPL forging on teacup_t31x.
# Keep the stock SPL path user-supplied since it is host/workspace specific.
# To auto-forge during build, pass T31_SECURE_BOOT=1 and T31_REFERENCE_SPL=<stock.bin>.

T31_NONCE_OFFSET ?= 0x30c0
T31_HASH_END ?= 0x4b80