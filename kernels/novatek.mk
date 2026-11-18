# Which kernel Novatek SoCs run: Novatek's 4.19.91 turnkey tree (tag
# REL_NT98529_SDK_TK_20250816, unchanged since the 20240201 release) with the
# thingino changes as commits on top. Pinned, because the vendor HDAL modules
# are matched to it by CRC.

KERNEL_SITE := https://github.com/gtxaspec/thingino-linux

ifeq ($(KERNEL_VERSION),)
KERNEL_VERSION := 4.19.91
endif

ifeq ($(KERNEL_VERSION),4.19.91)
ifeq ($(SOC_FAMILY),na51055)
KERNEL_BRANCH := novatek-na51055-4.19.91
KERNEL_HASH   := 0260740fd885eaa72e6569b848967a9ed4c9ec71
endif
endif
