# Which kernel Novatek SoCs run: the 4.19.91 turnkey tree, which Novatek has
# not changed since the 20240201 release (the 20250816 tags point at it too).
# Pinned, because the vendor HDAL modules are matched to it by CRC.

KERNEL_SITE := https://github.com/Novatek-OSS/kernel

ifeq ($(KERNEL_VERSION),)
KERNEL_VERSION := 4.19.91
endif

ifeq ($(KERNEL_VERSION),4.19.91)
ifeq ($(SOC_FAMILY),na51055)
KERNEL_BRANCH := REL_NT98529_SDK_TK_20250816
KERNEL_HASH   := 7cfb1551bd90058046db93757cbc5badfe9fe2bb
endif
endif
