WIFI_ATBM6162S_SITE_METHOD = git
WIFI_ATBM6162S_SITE = https://github.com/themactep/atbm-wifi
WIFI_ATBM6162S_SITE_BRANCH = kernel-7.x-atbm6062s
WIFI_ATBM6162S_VERSION = be198b361c7f85efdd0e49a9208d6a5f8f724573

WIFI_ATBM6162S_LICENSE = GPL-2.0

ATBM6162S_MODULE_NAME = atbm6162s
ATBM6162S_MODULE_OPTS = atbm_printk_mask=0

WIFI_ATBM6162S_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR)

define WIFI_ATBM6162S_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
	# wext compat so the interface shows up in /proc/net/wireless, which the
	# wifi init polls to detect when the driver has come up.
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211_WEXT)
	# The driver vendors its own mac80211 (hal_apollo/mac80211) and references
	# no kernel mac80211 symbol, only cfg80211. Building the kernel's mac80211
	# as well just wastes ~300K of the tiny kernel partition.
	$(call KCONFIG_DISABLE_OPT,CONFIG_MAC80211)
endef

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

define WIFI_ATBM6162S_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -D -m 0644 $(WIFI_ATBM6162S_PKGDIR)/files/firmware_sdio_ocea.bin \
		$(TARGET_DIR)/usr/lib/firmware/$(call qstrip,$(ATBM6162S_MODULE_NAME))_fw.bin
endef

WIFI_ATBM6162S_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6162S_INSTALL_CONFIGS

define WIFI_ATBM6162S_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(WIFI_ATBM6162S_PKGDIR)/files/atbm6162s.config \
		$(@D)/.config
	cp $(@D)/Kbuild.4.4 $(@D)/Kbuild
	$(SED) 's/^\(CONFIG_[A-Za-z0-9_]*\)="\(.*\)"$$/\1=\2/' $(@D)/.config
endef

WIFI_ATBM6162S_PRE_CONFIGURE_HOOKS += WIFI_ATBM6162S_COPY_CONFIG

$(eval $(kernel-module))
$(eval $(generic-package))
