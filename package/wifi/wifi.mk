# export UIMAGE_NAME = Linux-$(LINUX_VERSION_PROBED)-$(SOC_MODEL)
## Exclude buildroot yylloc patches
#LINUX_POST_PATCH_HOOKS = LINUX_APPLY_LOCAL_PATCHES

### Kernel configuration

#ifeq ($(BR2_PACKAGE_WIFI_AT9K),y)
#define WIFI_FIXUPS_AT9K
#	$(call KCONFIG_SET_OPT,CONFIG_ATH_CARDS,m)
#	$(call KCONFIG_SET_OPT,CONFIG_ATH9K,m)
#	$(call KCONFIG_SET_OPT,CONFIG_ATH9K_HTC,m)
#	$(call KCONFIG_SET_OPT,CONFIG_WLAN_VENDOR_ATH,y)
#endef
#define WIFI_INSTALL_AT9K
#	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/firmware/ath9k_htc
#	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/firmware/ath9k_htc $(WIFI_PKGDIR)/files/ath9k_htc/htc_9271-1.4.0.fw
#endef
#endif

#	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/firmware/mediatek
#	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/firmware/mediatek $(WIFI_PKGDIR)/files/mediatek/mt7601u.bin
#	ln -s mediatek/mt7601u.bin $(TARGET_DIR)/lib/firmware/mt7601u.bin
#	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/mediatek
#	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/mediatek $(WIFI_PKGDIR)/files/mediatek/RT2870STA.dat
# 	define WIFI_INSTALL_MT7601U
# 	endef

#	$(call KCONFIG_ENABLE_OPT,CONFIG_FW_LOADER)
#	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211)
#	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN_VENDOR_MEDIATEK)

#ifeq ($(BR2_PACKAGE_WIFI_MT7601U),y)
#define WIFI_FIXUPS_MT6701U
#	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211_WEXT)
#	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211_DEFAULT_PS)
#	$(call KCONFIG_SET_OPT,MT7601_STA,m)
#endef
#define WIFI_INSTALL_MT6701U
#endef
#endif

#ifeq ($(BR2_PACKAGE_WIFI_RTL8188EU),y)
#define WIFI_FIXUPS_RTL8188EU
#endef
#define WIFI_INSTALL_RTL8188EU
#	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/firmware/rtlwifi
#	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/firmware/rtlwifi $(WIFI_PKGDIR)/files/rtlwifi/rtl8188eufw.bin
#endef
#endif
#	$(WIFI_INSTALL_AT9K)
#	$(WIFI_INSTALL_MT7601U)
#	$(WIFI_INSTALL_RTL8188EU)
#	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
#	$(call KCONFIG_ENABLE_OPT,CONFIG_RFKILL)

define WIFI_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211,y)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL_HT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_DEFAULT_MINSTREL)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211_RC_DEFAULT,"minstrel_ht")

	$(WIFI_FIXUPS_AT9K)
	$(WIFI_FIXUPS_MT6701U)
	$(WIFI_FIXUPS_RTL8188EU)
endef

define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(WIFI_PKGDIR)/files/httpd-portal.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S38wireless
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S39wpa_supplicant

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(WIFI_PKGDIR)/files/wlan0

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www-portal
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www-portal/ $(WIFI_PKGDIR)/files/index.html
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www-portal/cgi-bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/var/www-portal/cgi-bin/ $(WIFI_PKGDIR)/files/update.cgi
endef

$(eval $(generic-package))
