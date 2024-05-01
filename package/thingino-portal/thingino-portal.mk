define THINGINO_PORTAL_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/udhcpd.conf $(TARGET_DIR)/etc/udhcpd.conf
    $(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/wpa_ap.conf $(TARGET_DIR)/etc/wpa_ap.conf
    $(INSTALL) -D -m 0755 $(THINGINO_PORTAL_PKGDIR)/files/S41portal $(TARGET_DIR)/etc/init.d/S41portal
endef

$(eval $(generic-package))
