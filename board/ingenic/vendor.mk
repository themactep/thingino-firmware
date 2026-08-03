# Ingenic-specific build rules for the top-level Makefile.
#
# Included via SOC_VENDOR_MK. A vendor that does not build its bootloader from
# package/thingino-uboot leaves VENDOR_BOOTLOADER_TARGETS empty.

# Targets that produce $(U_BOOT_BIN). thingino-uboot wraps gtxaspec/u-boot-ingenic,
# whose defconfig is derived per SoC, so the tree is cleaned before every rebuild.
VENDOR_BOOTLOADER_TARGETS := uboot-dirclean uboot
