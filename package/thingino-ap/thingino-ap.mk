THINGINO_AP_SITE_METHOD = local
THINGINO_AP_SITE = $(BR2_EXTERNAL)/package/thingino-ap

THINGINO_AP_NETDEV = wlan0
ifeq ($(BR2_PACKAGE_WIFI_HI3881),y)
THINGINO_AP_NETDEV = ap0
endif

define THINGINO_AP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/dnsd-ap.conf \
		$(TARGET_DIR)/etc/dnsd-ap.conf

	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/udhcpd-ap.conf \
		$(TARGET_DIR)/etc/udhcpd-ap.conf

	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/resolv-ap.conf \
		$(TARGET_DIR)/etc/resolv-ap.conf

	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/wpa_supplicant-ap.conf \
		$(TARGET_DIR)/etc/wpa_supplicant-ap.conf

	$(INSTALL) -d $(TARGET_DIR)/etc/init.d
	sed -e 's,@WLAN_AP_NETDEV@,$(THINGINO_AP_NETDEV),g' \
		$(THINGINO_AP_PKGDIR)/files/S42wifiap.in > \
		$(TARGET_DIR)/etc/init.d/S42wifiap
	chmod 0755 $(TARGET_DIR)/etc/init.d/S42wifiap

	$(INSTALL) -D -m 0755 $(THINGINO_AP_PKGDIR)/files/hosts-update \
		$(TARGET_DIR)/usr/sbin/hosts-update

	$(INSTALL) -d $(TARGET_DIR)/var/www/a/fonts
	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/bootstrap.min.css \
		$(TARGET_DIR)/var/www/a/bootstrap.min.css
	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/bootstrap.bundle.min.js \
		$(TARGET_DIR)/var/www/a/bootstrap.bundle.min.js
	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/bootstrap-icons.min.css \
		$(TARGET_DIR)/var/www/a/bootstrap-icons.min.css
	$(INSTALL) -D -m 0644 $(THINGINO_AP_PKGDIR)/files/bootstrap-icons.woff2 \
		$(TARGET_DIR)/var/www/a/fonts/bootstrap-icons.woff2
endef

$(eval $(generic-package))
