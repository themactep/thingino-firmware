define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S38wpa_supplicant
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S36wireless
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S39wifiauth

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(WIFI_PKGDIR)/files/wlan0
endef

define WIFI_INSTALL_WPA_SUPPLICANT_CONFIG
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/ $(WIFI_PKGDIR)/files/wpa_supplicant.conf
endef

WIFI_TARGET_FINALIZE_HOOKS += WIFI_INSTALL_WPA_SUPPLICANT_CONFIG

$(eval $(generic-package))
