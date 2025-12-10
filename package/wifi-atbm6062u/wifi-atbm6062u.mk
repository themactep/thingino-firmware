WIFI_ATBM6062U_VERSION = custom
WIFI_ATBM6062U_SITE = $(TOPDIR)/../atbm-wifi
WIFI_ATBM6062U_SITE_METHOD = local
WIFI_ATBM6062U_DEPENDENCIES = linux

WIFI_ATBM6062U_LICENSE = GPL-2.0

ATBM6062U_MODULE_NAME = "atbm6062s"

define WIFI_ATBM6062U_INSTALL_MODULES
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/extra
	$(INSTALL) -D -m 0644 $(@D)/hal_apollo/atbm6062s.ko \
		$(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/extra/atbm6062s.ko
endef

WIFI_ATBM6062U_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6062U_INSTALL_MODULES

define WIFI_ATBM6062U_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -D -m 0644 $(@D)/firmware/cronus_SDIO_NoBLE_SDIO_svn19514_24M_wifi6phy_DCDC.bin \
		$(TARGET_DIR)/lib/firmware/$(call qstrip,$(ATBM6062U_MODULE_NAME))_fw.bin
endef

WIFI_ATBM6062U_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6062U_INSTALL_CONFIGS

# Build like the standalone Makefile.build.customer does
define WIFI_ATBM6062U_CONFIGURE_CMDS
	$(INSTALL) -D -m 0644 $(@D)/configs/atbm6062u.config $(@D)/.config
endef

define WIFI_ATBM6062U_BUILD_CMDS
	@echo "Building hal_apollo/atbm6062u module with kernel 4.4 compat exports (SDIO, Ingenic T41)..."
	$(MAKE) -C $(LINUX_DIR) \
		ARCH=$(KERNEL_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		M=$(@D)/hal_apollo \
		PWD=$(@D) \
		CONFIG_ATBM_APOLLO_WIFI6=m \
		CONFIG_CRONUS=y \
		SDIO_BUS=y \
		EXTRA_CFLAGS="-DATBM_WIFI_PLATFORM=23 -DCONFIG_ATBM_SDIO_MMC_ID=\\\"mmc1\\\"" \
		MODULES_NAME=atbm6062u \
		ATBM_MODULES_NAME=atbm6062u \
		modules
endef

$(eval $(generic-package))
