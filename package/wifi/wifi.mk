define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S36wireless
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S38wpa_supplicant

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(WIFI_PKGDIR)/files/wlan0
endef

$(eval $(generic-package))
