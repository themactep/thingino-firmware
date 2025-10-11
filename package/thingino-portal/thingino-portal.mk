THINGINO_PORTAL_SITE_METHOD = local
THINGINO_PORTAL_SITE = $(BR2_EXTERNAL)/package/thingino-portal

define THINGINO_PORTAL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/dnsd-portal.conf \
		$(TARGET_DIR)/etc/dnsd-portal.conf

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/httpd-portal.conf \
		$(TARGET_DIR)/etc/httpd-portal.conf

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/udhcpd-portal.conf \
		$(TARGET_DIR)/etc/udhcpd-portal.conf

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/wpa-portal_ap.conf \
		$(TARGET_DIR)/etc/wpa-portal_ap.conf

	$(INSTALL) -D -m 0755 $(THINGINO_PORTAL_PKGDIR)/files/S41portal \
		$(TARGET_DIR)/etc/init.d/S41portal

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/favicon.ico \
		$(TARGET_DIR)/var/www-portal/favicon.ico

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/index.html \
		$(TARGET_DIR)/var/www-portal/index.html

	$(INSTALL) -D -m 0755 $(THINGINO_PORTAL_PKGDIR)/files/index.cgi \
		$(TARGET_DIR)/var/www-portal/x/index.cgi

	$(INSTALL) -D -m 0755 $(THINGINO_PORTAL_PKGDIR)/files/portal.cgi \
		$(TARGET_DIR)/var/www-portal/x/portal.cgi

	find $(TARGET_DIR)/var/www-portal/x/ -type f -name *.cgi -exec chmod 755 {} \;

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/bootstrap.bundle.min.js \
		$(TARGET_DIR)/var/www/a/bootstrap.bundle.min.js

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/bootstrap.min.css \
		$(TARGET_DIR)/var/www/a/bootstrap.min.css

	$(INSTALL) -D -m 0644 $(THINGINO_PORTAL_PKGDIR)/files/logo.svg \
		$(TARGET_DIR)/var/www/a/logo.svg

	find $(TARGET_DIR)/var/www/a/ -type f \( -name "*.css" -o -name "*.ico" -o -name "*.js" -o -name "*.svg" \) -exec gzip {} \;

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www-portal/a

	ln -sr $(TARGET_DIR)/var/www/a/bootstrap.min.css.gz \
		$(TARGET_DIR)/var/www-portal/a/
	ln -sr $(TARGET_DIR)/var/www/a/bootstrap.bundle.min.js.gz \
		$(TARGET_DIR)/var/www-portal/a/
	ln -sr $(TARGET_DIR)/var/www/a/logo.svg.gz \
		$(TARGET_DIR)/var/www-portal/a/
endef

# MT7601u wifi driver needs a PSK for the portal AP to function
ifeq ($(BR2_PACKAGE_WIFI_MT7601U),y)
define MODIFY_INSTALL_CONFIGS
	sed -i '/key_mgmt/s/NONE/WPA-PSK/' $(TARGET_DIR)/etc/wpa-portal_ap.conf
	sed -i '/network={/a\      psk="thingino"' $(TARGET_DIR)/etc/wpa-portal_ap.conf
endef
endif

THINGINO_PORTAL_POST_INSTALL_TARGET_HOOKS += MODIFY_INSTALL_CONFIGS

$(eval $(generic-package))
