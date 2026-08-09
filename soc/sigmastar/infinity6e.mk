# SigmaStar Infinity6E family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),ssc30kq),)

SOC_FAMILY := infinity6e
SOC_ARCH   := infinity6e
# The board's own LX_MEM=0xFFE0000.
SOC_RAM_MB := 256

# No SOC_UBOOT_*: the bootloader stays on the chip, so BR2_TARGET_UBOOT is unused.

endif
