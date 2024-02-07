$(info --- FILE: external.mk ---)

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
KERNEL_BRANCH = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T15),y)
KERNEL_BRANCH = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T20),y)
KERNEL_BRANCH = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T21),y)
KERNEL_BRANCH = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T23),y)
KERNEL_BRANCH = $(SOC_VENDOR)-t31
else ifeq ($(BR2_SOC_INGENIC_T30),y)
KERNEL_BRANCH = $(SOC_VENDOR)-t31
else
KERNEL_BRANCH = $(SOC_VENDOR)-$(SOC_FAMILY)
endif

### Packages

THINGINO_KERNEL = "https://github.com/gtxaspec/openipc_linux/archive/$(KERNEL_BRANCH).tar.gz"

# if config file uses external toolchain, use it
#ifneq ($(BR2_TOOLCHAIN_EXTERNAL),)
#OPENIPC_TOOLCHAIN = latest/$(shell $(SCRIPTS_DIR)/show_toolchains.sh $(BOARD_CONFIG))
#export BR2_TOOLCHAIN_EXTERNAL=y
#OUTPUT_DIR := $(OUTPUT_DIR)-ext
#endif

export SOC_VENDOR
export SOC_FAMILY
export SOC_MODEL
export THINGINO_KERNEL

# include makefiles from packages
include $(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk))
