################################################################################
#
# novatek-uboot
#
################################################################################

# Novatek's REL_NT98529_SDK_TK_20260109 (U-Boot 2021.10) with the thingino changes on top
NOVATEK_UBOOT_SITE = https://github.com/gtxaspec/u-boot-novatek
NOVATEK_UBOOT_SITE_METHOD = git
NOVATEK_UBOOT_VERSION = d8f4ebe55b45532b98fe394b316c1b82e38c64de
NOVATEK_UBOOT_LICENSE = GPL-2.0+
NOVATEK_UBOOT_LICENSE_FILES = Licenses/gpl-2.0.txt
NOVATEK_UBOOT_INSTALL_TARGET = YES
NOVATEK_UBOOT_INSTALL_IMAGES = YES
NOVATEK_UBOOT_DEPENDENCIES = host-uboot-tools

# Must match CONFIG_ENV_SIZE in env-*.fragment
NOVATEK_UBOOT_ENV_SIZE = 0x10000

NOVATEK_UBOOT_BOARD_DIR = $(BR2_EXTERNAL_THINGINO_PATH)/board/novatek/$(SOC_FAMILY)/uboot

ifeq ($(BR2_PACKAGE_NOVATEK_UBOOT_BOOT_SD),y)
NOVATEK_UBOOT_MEDIA = sd
else ifeq ($(BR2_PACKAGE_NOVATEK_UBOOT_BOOT_NAND),y)
NOVATEK_UBOOT_MEDIA = nand
endif
NOVATEK_UBOOT_ENV = $(NOVATEK_UBOOT_BOARD_DIR)/$(NOVATEK_UBOOT_MEDIA).env

NOVATEK_UBOOT_MAKE_OPTS = \
	ARCH=arm \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	HOSTCC="$(HOSTCC)" \
	HOSTCFLAGS="$(HOST_CFLAGS) -fcommon" \
	NVT_PRJCFG_MODEL_CFG=$(NOVATEK_UBOOT_BOARD_DIR)/$(SOC_MODEL).mk

define NOVATEK_UBOOT_CONFIGURE_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(NOVATEK_UBOOT_MAKE_OPTS) nvt-na51055_a32_nand_defconfig
	cd $(@D) && ARCH=arm scripts/kconfig/merge_config.sh -m .config \
		$(NOVATEK_UBOOT_BOARD_DIR)/thingino.fragment \
		$(NOVATEK_UBOOT_BOARD_DIR)/env-$(NOVATEK_UBOOT_MEDIA).fragment
	echo 'CONFIG_DEFAULT_ENV_FILE="$(NOVATEK_UBOOT_ENV)"' >> $(@D)/.config
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(NOVATEK_UBOOT_MAKE_OPTS) olddefconfig
endef

define NOVATEK_UBOOT_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) $(NOVATEK_UBOOT_MAKE_OPTS)
endef

# The loader checks the bin-info stamp at 0x350, as the SDK's encrypt_bin SUM writes it
# The image carries the environment, so it is valid from the first boot and fw_setenv never
# starts from an empty one
define NOVATEK_UBOOT_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/u-boot.bin $(BINARIES_DIR)/u-boot.bin
	python3 $(BR2_EXTERNAL_THINGINO_PATH)/scripts/nvtpack.py binsum $(BINARIES_DIR)/u-boot.bin
	sed -e '/^#/d' -e '/^$$/d' $(NOVATEK_UBOOT_ENV) > $(BINARIES_DIR)/u-boot-env.txt
	$(HOST_DIR)/bin/mkenvimage -s $(NOVATEK_UBOOT_ENV_SIZE) -o $(BINARIES_DIR)/u-boot-env.bin \
		$(BINARIES_DIR)/u-boot-env.txt
endef

# fw_printenv/fw_setenv reach the same environment U-Boot keeps; the overlay carries an
# Ingenic /etc/fw_env.config, so scripts/rootfs_script.sh moves this one over it
define NOVATEK_UBOOT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(NOVATEK_UBOOT_BOARD_DIR)/fw_env-$(NOVATEK_UBOOT_MEDIA).config \
		$(TARGET_DIR)/usr/share/u-boot/fw_env.config
endef

$(eval $(generic-package))
