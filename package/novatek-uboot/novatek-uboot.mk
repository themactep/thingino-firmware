################################################################################
#
# novatek-uboot
#
################################################################################

# REL_NT98529_SDK_TK_20260109
NOVATEK_UBOOT_VERSION = 738e681c46f09368e0178905c94676dc5c15e1e4
NOVATEK_UBOOT_SITE = https://github.com/Novatek-OSS/u-boot/archive
NOVATEK_UBOOT_SOURCE = $(NOVATEK_UBOOT_VERSION).tar.gz
NOVATEK_UBOOT_LICENSE = GPL-2.0+
NOVATEK_UBOOT_LICENSE_FILES = Licenses/gpl-2.0.txt
NOVATEK_UBOOT_INSTALL_TARGET = NO
NOVATEK_UBOOT_INSTALL_IMAGES = YES

NOVATEK_UBOOT_BOARD_DIR = $(BR2_EXTERNAL_THINGINO_PATH)/board/novatek/$(SOC_FAMILY)/uboot

ifeq ($(BR2_PACKAGE_NOVATEK_UBOOT_BOOT_SD),y)
NOVATEK_UBOOT_ENV = $(NOVATEK_UBOOT_BOARD_DIR)/sd.env
else ifeq ($(BR2_PACKAGE_NOVATEK_UBOOT_BOOT_NAND),y)
NOVATEK_UBOOT_ENV = $(NOVATEK_UBOOT_BOARD_DIR)/nand.env
endif

NOVATEK_UBOOT_MAKE_OPTS = \
	ARCH=arm \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	HOSTCC="$(HOSTCC)" \
	HOSTCFLAGS="$(HOST_CFLAGS) -fcommon" \
	NVT_PRJCFG_MODEL_CFG=$(NOVATEK_UBOOT_BOARD_DIR)/$(SOC_MODEL).mk

define NOVATEK_UBOOT_CONFIGURE_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(NOVATEK_UBOOT_MAKE_OPTS) nvt-na51055_a32_nand_defconfig
	cd $(@D) && ARCH=arm scripts/kconfig/merge_config.sh -m .config \
		$(NOVATEK_UBOOT_BOARD_DIR)/thingino.fragment
	echo 'CONFIG_DEFAULT_ENV_FILE="$(NOVATEK_UBOOT_ENV)"' >> $(@D)/.config
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(NOVATEK_UBOOT_MAKE_OPTS) olddefconfig
endef

define NOVATEK_UBOOT_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(NOVATEK_UBOOT_MAKE_OPTS)
endef

# The loader checks the bin-info stamp at 0x350, as the SDK's encrypt_bin SUM writes it
define NOVATEK_UBOOT_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/u-boot.bin $(BINARIES_DIR)/u-boot.bin
	python3 $(BR2_EXTERNAL_THINGINO_PATH)/scripts/nvtpack.py binsum $(BINARIES_DIR)/u-boot.bin
endef

$(eval $(generic-package))
