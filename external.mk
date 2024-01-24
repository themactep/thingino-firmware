$(info --- FILE: external.mk ---)

#ifeq ($(FLASH_SIZE_MB),32)
#FLASH_SIZE_HEX := 0x2000000
#else ifeq ($(FLASH_SIZE_MB),16)
#FLASH_SIZE_HEX := 0x1000000
#else ifeq ($(FLASH_SIZE_MB),8)
#FLASH_SIZE_HEX := 0x800000
#else
#$(error Flash size is not set in defconfig)
#endif

SOC_VENDOR := ingenic

ifeq ($(BR2_SOC_INGENIC_T10),y)
SOC_MODEL := t10
SOC_FAMILY := t10
else ifeq ($(BR2_SOC_INGENIC_T15),y)
SOC_MODEL := t15
SOC_FAMILY := t15
else ifeq ($(BR2_SOC_INGENIC_T20),y)
SOC_MODEL := t20
SOC_FAMILY := t20
else ifeq ($(BR2_SOC_INGENIC_T21),y)
SOC_MODEL := t21
SOC_FAMILY := t21
else ifeq ($(BR2_SOC_INGENIC_T23),y)
SOC_MODEL := t23
SOC_FAMILY := t23
else ifeq ($(BR2_SOC_INGENIC_T30),y)
SOC_MODEL := t30
SOC_FAMILY := t30
else ifeq ($(BR2_SOC_INGENIC_T31),y)
SOC_MODEL := t31
SOC_FAMILY := t31
else ifeq ($(BR2_SOC_INGENIC_T40),y)
SOC_MODEL := t40
SOC_FAMILY := t40
else ifeq ($(BR2_SOC_INGENIC_T41),y)
SOC_MODEL := t41
SOC_FAMILY := t41
endif

ifeq (BR2_SOC_INGENIC_T31,y)
BR2_PACKAGE_INGENIC_MOTORS_T31=y
BR2_PACKAGE_INGENIC_OSDRV_T31=y
else ifeq (BR2_SOC_INGENIC_T20,y)
BR2_PACKAGE_INGENIC_OSDRV_T20=y
endif

ifeq ($(BR2_SOC_INGENIC_T10),y)
BR2_KERNEL = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T15),y)
BR2_KERNEL = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T20),y)
BR2_KERNEL = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T21),y)
BR2_KERNEL = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T23),y)
BR2_KERNEL = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T30),y)
BR2_KERNEL = $(SOC_VENDOR)-t31
else
BR2_KERNEL = $(SOC_VENDOR)-$(SOC_FAMILY)
endif

### Packages

#ifeq ($(call qstrip,$(BR2_DL_DIR)),$(TOPDIR)/dl)
OPENIPC_KERNEL = $(BR2_KERNEL)
#else
#OPENIPC_KERNEL = $(shell git ls-remote https://github.com/openipc/linux $(BR2_KERNEL) | head -1 | cut -f1)
#LOCAL_DOWNLOAD = y
#endif

# if config file uses external toolchain, use it
ifneq ($(BR2_TOOLCHAIN_EXTERNAL),)
OPENIPC_TOOLCHAIN = latest/$(shell $(SCRIPTS_DIR)/show_toolchains.sh $(BOARD_CONFIG))
export BR2_TOOLCHAIN_EXTERNAL=y
OUTPUT_DIR := $(OUTPUT_DIR)-ext
endif

export SOC_VENDOR
export SOC_FAMILY
export SOC_MODEL
export OPENIPC_KERNEL

# include makefiles from packages
include $(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk))
