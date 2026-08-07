# SigmaStar Infinity6E family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),ssc30kq),)

SOC_FAMILY := infinity6e
# Selects a board/kernel subdirectory. For Ingenic that is an ISA shared by
# several families; here the family is the finest split that exists, so the two
# coincide.
SOC_ARCH   := infinity6e

# The DRAM is inside the SoC package, so a board cannot choose it. Reaches
# .config as BR2_SOC_RAM_MB, whose only consumers are the Ingenic ISP module's
# rmem/nmem defaults -- this vendor carves memory out in the U-Boot bootargs
# instead, but the value should still describe the hardware: 256MB is the
# board's own LX_MEM=0xFFE0000, 268304384 bytes.
SOC_RAM_MB := 256

# No SOC_UBOOT_*: this vendor keeps its bootloader on the chip and does not use
# BR2_TARGET_UBOOT.

endif
