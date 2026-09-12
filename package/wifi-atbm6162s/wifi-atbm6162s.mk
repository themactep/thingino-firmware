WIFI_ATBM6162S_SITE_METHOD = git
WIFI_ATBM6162S_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_ATBM6162S_SITE_BRANCH = atbm-606x-c
WIFI_ATBM6162S_VERSION = 8d06d948cc0d24405faf5429cd4bebf95640d705

WIFI_ATBM6162S_LICENSE = GPL-2.0

ATBM6162S_MODULE_NAME = atbm6162s
ATBM6162S_MODULE_OPTS = atbm_printk_mask=0

WIFI_ATBM6162S_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR)

define WIFI_ATBM6162S_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	# atbm6162s is a self-contained backports package: it builds its OWN cfg80211
	# (CONFIG_CPTCFG_CFG80211=y in its config, newer API) and bundles mac80211 inside
	# atbm6162s.ko. The kernel's 4.4.94 cfg80211/mac80211 MUST be off: linking them
	# against the driver's newer bundled headers is an ABI mismatch (e.g. cfg80211_scan_done
	# signature differs) that corrupts kernel memory. See CPTCFG_CFG80211 help: "<5.7 -> open".
	$(call KCONFIG_DISABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_DISABLE_OPT,CONFIG_MAC80211)
endef

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

define WIFI_ATBM6162S_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -D -m 0644 $(@D)/firmware/firmware_sdio_ocea.bin \
		$(TARGET_DIR)/usr/lib/firmware/$(call qstrip,$(ATBM6162S_MODULE_NAME))_fw.bin
endef

WIFI_ATBM6162S_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6162S_INSTALL_CONFIGS

define WIFI_ATBM6162S_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(@D)/configs/atbm6162s.config \
		$(@D)/.config
endef

WIFI_ATBM6162S_PRE_CONFIGURE_HOOKS += WIFI_ATBM6162S_COPY_CONFIG

$(eval $(kernel-module))
$(eval $(generic-package))
