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
endef

define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(WIFI_PKGDIR)/files/httpd-portal.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S36wireless
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S38wpa_supplicant

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(WIFI_PKGDIR)/files/wlan0

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www-portal
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www-portal/ $(WIFI_PKGDIR)/files/index.html
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www-portal/ $(WIFI_PKGDIR)/files/favicon.ico

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www-portal/cgi-bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/var/www-portal/cgi-bin/ $(WIFI_PKGDIR)/files/index.cgi

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www/a $(WIFI_PKGDIR)/files/bootstrap.min.css
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www/a $(WIFI_PKGDIR)/files/bootstrap.bundle.min.js

	ln -sr $(TARGET_DIR)/var/www/a/bootstrap.min.css       $(TARGET_DIR)/var/www-portal/
	ln -sr $(TARGET_DIR)/var/www/a/bootstrap.bundle.min.js $(TARGET_DIR)/var/www-portal/
endef

$(eval $(generic-package))
