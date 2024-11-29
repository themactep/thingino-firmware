define THINGINO_AP_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_AP_PKGDIR)/files/dnsd-ap.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_AP_PKGDIR)/files/udhcpd-ap.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_AP_PKGDIR)/files/resolv-ap.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_AP_PKGDIR)/files/wpa-ap.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(THINGINO_AP_PKGDIR)/files/S42wifiap

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin/ $(THINGINO_AP_PKGDIR)/files/hosts-update
endef

$(eval $(generic-package))
