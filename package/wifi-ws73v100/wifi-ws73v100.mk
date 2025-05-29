WIFI_WS73V100_SITE_METHOD = git
WIFI_WS73V100_SITE = https://github.com/gtxaspec/ws73v100-wifi
WIFI_WS73V100_SITE_BRANCH = master
WIFI_WS73V100_VERSION = 163935b988d9c0eb7e98338badd713d2118ee638
# $(shell git ls-remote $(WIFI_WS73V100_SITE) $(WIFI_WS73V100_SITE_BRANCH) | head -1 | cut -f1)

WIFI_WS73V100_LICENSE = GPL-2.0

WS73V100_MODULE_NAME = ws73v100

define WIFI_WS73V100_CONFIGURE_OPTIONS
	# Configure build environment
	sed -i 's|^WSCFG_KERNEL_DIR=.*|WSCFG_KERNEL_DIR=$(LINUX_DIR)|' $(@D)/build/config/ws73_default.config
	sed -i 's|^WSCFG_CROSS_COMPILE=.*|WSCFG_CROSS_COMPILE=$(TARGET_CROSS)|' $(@D)/build/config/ws73_default.config
	sed -i 's|^WSCFG_ARCH_NAME=.*|WSCFG_ARCH_NAME=$(KERNEL_ARCH)|' $(@D)/build/config/ws73_default.config
	sed -i 's|^WSCFG_ARCH_ARM=.*|WSCFG_ARCH_ARM=n|' $(@D)/build/config/ws73_default.config
	# Configure bus interface
	$(if $(BR2_PACKAGE_WIFI_WS73V100_USB), \
		sed -i 's/^WSCFG_BUS_SDIO=.*/WSCFG_BUS_SDIO=n/' $(@D)/build/config/ws73_default.config && \
		sed -i 's/^WSCFG_BUS_USB=.*/WSCFG_BUS_USB=y/' $(@D)/build/config/ws73_default.config, \
		$(if $(BR2_PACKAGE_WIFI_WS73V100_SDIO), \
			sed -i 's/^WSCFG_BUS_SDIO=.*/WSCFG_BUS_SDIO=y/' $(@D)/build/config/ws73_default.config && \
			sed -i 's/^WSCFG_BUS_USB=.*/WSCFG_BUS_USB=n/' $(@D)/build/config/ws73_default.config))
	# Configure firmware and config file paths
	sed -i 's|^CONFIG_FIRMWARE_BIN_PATH=.*|CONFIG_FIRMWARE_BIN_PATH="/usr/lib/firmware/ws73.bin"|' $(@D)/build/config/ws73_default.config
	sed -i 's|^CONFIG_FIRMWARE_WIFICALI_PATH=.*|CONFIG_FIRMWARE_WIFICALI_PATH="/usr/lib/firmware/wifi_cali.bin"|' $(@D)/build/config/ws73_default.config
	sed -i 's|^CONFIG_FIRMWARE_BSLECALI_PATH=.*|CONFIG_FIRMWARE_BSLECALI_PATH="/usr/lib/firmware/btc_cali.bin"|' $(@D)/build/config/ws73_default.config
	sed -i 's|^CONFIG_FIRMWARE_WOW_PATH=.*|CONFIG_FIRMWARE_WOW_PATH="/usr/lib/firmware/wow.bin"|' $(@D)/build/config/ws73_default.config
	sed -i 's|^CONFIG_INI_FILE_PATH=.*|CONFIG_INI_FILE_PATH="/usr/share/wifi/ws73_cfg.ini"|' $(@D)/build/config/ws73_default.config
endef

WIFI_WS73V100_PRE_BUILD_HOOKS += WIFI_WS73V100_CONFIGURE_OPTIONS

define WIFI_WS73V100_LINUX_CONFIG_FIXUPS
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

define WIFI_WS73V100_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) platform wifi -C $(@D)
endef

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

define WIFI_WS73V100_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))
	touch $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -D -m 0644 $(@D)/output/bin/ws73_cfg.ini \
		$(TARGET_DIR)/usr/share/wifi/ws73_cfg.ini

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/firmware
	$(INSTALL) -D -m 0644 $(@D)/firmware/us/*.bin \
		$(TARGET_DIR)/usr/lib/firmware
endef

WIFI_WS73V100_POST_INSTALL_TARGET_HOOKS += WIFI_WS73V100_INSTALL_CONFIGS

define WIFI_WS73V100_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/output/bin/plat_soc.ko \
		$(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))/extra/plat_soc.ko

	$(INSTALL) -D -m 0755 $(@D)/output/bin/wifi_soc.ko \
		$(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))/extra/plat_wifi.ko
endef

$(eval $(kernel-module))
$(eval $(generic-package))
