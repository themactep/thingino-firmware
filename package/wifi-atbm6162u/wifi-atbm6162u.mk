WIFI_ATBM6162U_SITE_METHOD = git
WIFI_ATBM6162U_SITE = https://github.com/themactep/atbm-wifi
WIFI_ATBM6162U_SITE_BRANCH = kernel-7.x-atbm6062s
WIFI_ATBM6162U_VERSION = be198b361c7f85efdd0e49a9208d6a5f8f724573

WIFI_ATBM6162U_LICENSE = GPL-2.0

# FIXME: intermittent kernel crash in the vendored mac80211 teardown when the
# interface is brought down (rcK does this on reboot/shutdown). Sometimes kfree()
# is called on an already-freed / non-slab pointer, oopsing the kernel and
# wedging the reboot until the hardware watchdog fires (~60 s).
# Trace tail on 4.4.94 with 6f4f122 (all in this package's bundled mac80211):
#   kfree
#   __ieee80211_key_destroy        (hal_apollo/mac80211/key.c)
#   __sta_info_destroy             (hal_apollo/mac80211/sta_info.c, gtk/ptk free block)
#   sta_info_flush / ieee80211_mgd_deauth
#   cfg80211_mlme_deauth / cfg80211_mlme_down / cfg80211_disconnect / cfg80211_leave
# Suspect the station PTK teardown (__ieee80211_key_free / __ieee80211_key_replace,
# and whether sta->ptk is NULLed) and the vendor CONFIG_MAC80211_ATBM_ROAMING_CHANGES
# async sta/key free. Reproduces only from long-lived / manually-brought-up
# sessions; a guarded kfree did NOT catch a double free during forced ifdown and
# rcK runs. Upstream branch atbm-606x-c has no fix as of this version.
ATBM6162U_MODULE_NAME = atbm6162u
ATBM6162U_MODULE_OPTS = atbm_printk_mask=0

WIFI_ATBM6162U_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR)

define WIFI_ATBM6162U_LINUX_CONFIG_FIXUPS
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

define WIFI_ATBM6162U_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -D -m 0644 $(WIFI_ATBM6162U_PKGDIR)/files/firmware_usb_ocea.bin \
		$(TARGET_DIR)/usr/lib/firmware/$(call qstrip,$(ATBM6162U_MODULE_NAME))_fw.bin
endef

WIFI_ATBM6162U_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6162U_INSTALL_CONFIGS

define WIFI_ATBM6162U_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(WIFI_ATBM6162U_PKGDIR)/files/atbm6162u.config \
		$(@D)/.config
	$(SED) 's/^# CONFIG_CPTCFG_CFG80211 is not set/CONFIG_CPTCFG_CFG80211=y\nCONFIG_CPTCFG_CFG80211_WEXT=y/' \
		$(@D)/.config
	$(SED) 's/^\(CONFIG_[A-Za-z0-9_]*\)="\(.*\)"$$/\1=\2/' $(@D)/.config
endef

WIFI_ATBM6162U_PRE_CONFIGURE_HOOKS += WIFI_ATBM6162U_COPY_CONFIG

$(eval $(kernel-module))
$(eval $(generic-package))
