WIFI_ATBM6132CU_SITE_METHOD = git
WIFI_ATBM6132CU_SITE = https://github.com/themactep/atbm-wifi
WIFI_ATBM6132CU_SITE_BRANCH = kernel-7.x-atbm6062s
WIFI_ATBM6132CU_VERSION = be198b361c7f85efdd0e49a9208d6a5f8f724573

WIFI_ATBM6132CU_LICENSE = GPL-2.0

ATBM6132CU_MODULE_NAME = atbm6132cu

# The 6132cu ships as USB DID 0x6055 (wifi-only) and 0x6162 (BT-comb). The
# 0x6162 part must run the comb firmware with wifi_bt_comb=1 or transmit stalls
# a minute or two after association; its validated config also drops MODULE_FS
# (and with it the atbm_printk_mask parameter) and takes p2p0/mon0 out.
ifeq ($(BR2_PACKAGE_WIFI_ATBM6132CU_6162),y)
WIFI_ATBM6132CU_CONFIG = atbm6132cu_6162.config
ATBM6132CU_MODULE_OPTS = wifi_bt_comb=1
ATBM6132CU_FIRMWARE = firmware_usb_wifi_bt_comb_ocea.bin
else
WIFI_ATBM6132CU_CONFIG = atbm6132cu_ingenic.config
ATBM6132CU_MODULE_OPTS = atbm_printk_mask=0
ifeq ($(BR2_PACKAGE_THINGINO_BLUETOOTH),y)
ATBM6132CU_MODULE_OPTS += wifi_bt_comb=1
ATBM6132CU_FIRMWARE = firmware_usb_wifi_bt_comb_ocea.bin
WIFI_ATBM6132CU_PRE_CONFIGURE_HOOKS += WIFI_ATBM6132CU_COPY_CONFIG_BLE
else
ATBM6132CU_FIRMWARE = firmware_usb_ocea.bin
endif
endif

WIFI_ATBM6132CU_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR)

define WIFI_ATBM6132CU_LINUX_CONFIG_FIXUPS
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

define WIFI_ATBM6132CU_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)
	touch $(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt
	$(INSTALL) -m 0644 $(WIFI_ATBM6132CU_PKGDIR)/files/set_rate_power_5g.txt \
		$(TARGET_DIR)/usr/share/wifi/set_rate_power_5g.txt
endef

define WIFI_ATBM6132CU_INSTALL_FIRMWARE
	$(INSTALL) -D -m 0644 $(WIFI_ATBM6132CU_PKGDIR)/files/$(ATBM6132CU_FIRMWARE) \
		$(TARGET_DIR)/usr/lib/firmware/$(call qstrip,$(ATBM6132CU_MODULE_NAME))_fw.bin
endef

define WIFI_ATBM6132CU_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(WIFI_ATBM6132CU_PKGDIR)/files/$(WIFI_ATBM6132CU_CONFIG) \
		$(@D)/.config
	# The driver's Kbuild uses the raw Kconfig values; strip the quotes.
	$(SED) 's/^\(CONFIG_[A-Za-z0-9_]*\)="\(.*\)"$$/\1=\2/' $(@D)/.config
endef

define WIFI_ATBM6132CU_COPY_CONFIG_BLE
	echo "CONFIG_ATBM_BLE_WIFI6=y" >> $(@D)/.config
	echo "CONFIG_ATBM_BLE_WIFI_PLATFORM_WIFI6=y" >> $(@D)/.config
endef

WIFI_ATBM6132CU_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6132CU_INSTALL_CONFIGS
WIFI_ATBM6132CU_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6132CU_INSTALL_FIRMWARE
WIFI_ATBM6132CU_PRE_CONFIGURE_HOOKS += WIFI_ATBM6132CU_COPY_CONFIG

$(eval $(kernel-module))
$(eval $(generic-package))
