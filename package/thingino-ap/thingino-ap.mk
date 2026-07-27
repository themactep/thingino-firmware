THINGINO_AP_SITE_METHOD = local
THINGINO_AP_SITE = $(BR2_EXTERNAL)/package/thingino-ap

define THINGINO_AP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/dnsd-ap.conf \
		$(TARGET_DIR)/etc/dnsd-ap.conf

	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/udhcpd-ap.conf \
		$(TARGET_DIR)/etc/udhcpd-ap.conf

	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/resolv-ap.conf \
		$(TARGET_DIR)/etc/resolv-ap.conf

	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/wpa-ap.conf \
		$(TARGET_DIR)/etc/wpa-ap.conf

	$(INSTALL) -D -m 0755 $(THINGINO_AP_PKGDIR)/files/S42wifiap \
		$(TARGET_DIR)/etc/init.d/S42wifiap

	$(INSTALL) -D -m 0755 $(THINGINO_AP_PKGDIR)/files/hosts-update \
		$(TARGET_DIR)/usr/sbin/hosts-update
endef

$(eval $(generic-package))
