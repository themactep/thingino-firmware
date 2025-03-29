WIFI_AIC8800_SITE_METHOD = git
WIFI_AIC8800_SITE = https://github.com/gtxaspec/aic8800-wifi
WIFI_AIC8800_SITE_BRANCH = master
WIFI_AIC8800_VERSION = 4083241454a17f9632feae86d580cbaef7ef0985
#WIFI_AIC8800_VERSION = $(shell git ls-remote $(WIFI_AIC8800_SITE) $(WIFI_AIC8800_SITE_BRANCH) | head -1 | cut -f1)
WIFI_AIC8800_LICENSE = GPL-2.0

define WIFI_AIC8800_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211,y)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL_HT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_DEFAULT_MINSTREL)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211_RC_DEFAULT,"minstrel_ht")
endef

# USB driver path
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_USB),y)
WIFI_AIC8800_MODULE_SUBDIRS = USB/driver_fw/drivers/aic8800
endif

# SDIO driver path
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_SDIO),y)
WIFI_AIC8800_MODULE_SUBDIRS = SDIO/driver_fw/driver/aic8800
endif

# PCIE driver paths
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_PCIE),y)
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80),y)
WIFI_AIC8800_MODULE_SUBDIRS = PCIE/driver_fw/driver/aic8800/aic8800_fdrv
endif
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80X2),y)
WIFI_AIC8800_MODULE_SUBDIRS = PCIE/driver_fw/driver/aic8800d80x2/aic8800_fdrv
endif
endif

define WIFI_AIC8800_INSTALL_FIRMWARE
	# USB Models
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800/ \
			$(@D)/USB/driver_fw/fw/aic8800/*; \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800D80)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800D80; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800D80/ \
			$(@D)/USB/driver_fw/fw/aic8800D80/*; \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800D80X2)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800D80X2; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800D80X2/ \
			$(@D)/USB/driver_fw/fw/aic8800D80X2/*; \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800DC)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800DC; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800DC/ \
			$(@D)/USB/driver_fw/fw/aic8800DC/*; \
	fi

	# SDIO Models
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_SDIO_8800)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800/ \
			$(@D)/SDIO/driver_fw/fw/aic8800/*; \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_SDIO_8800D80)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800D80; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800D80/ \
			$(@D)/SDIO/driver_fw/fw/aic8800D80/*; \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_SDIO_8800DC)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800DC; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800DC/ \
			$(@D)/SDIO/driver_fw/fw/aic8800DC/*; \
	fi

	# PCIE Models
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800D80; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800D80/ \
			$(@D)/PCIE/driver_fw/fw/aic8800D80/*; \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80X2)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/firmware/aic8800D80X2; \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/lib/firmware/aic8800D80X2/ \
			$(@D)/PCIE/driver_fw/fw/aic8800D80X2/*; \
	fi
endef

WIFI_AIC8800_POST_INSTALL_TARGET_HOOKS += WIFI_AIC8800_INSTALL_FIRMWARE

$(eval $(kernel-module))
$(eval $(generic-package))
