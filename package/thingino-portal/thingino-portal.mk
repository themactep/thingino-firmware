define THINGINO_PORTAL_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_PORTAL_PKGDIR)/files/dnsd.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_PORTAL_PKGDIR)/files/httpd-portal.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_PORTAL_PKGDIR)/files/udhcpd.conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(THINGINO_PORTAL_PKGDIR)/files/wpa_ap.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(THINGINO_PORTAL_PKGDIR)/files/S41portal

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www-portal
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www-portal/ $(THINGINO_PORTAL_PKGDIR)/files/favicon.ico
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www-portal/ $(THINGINO_PORTAL_PKGDIR)/files/index.html

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www-portal/x
	$(INSTALL) -m 755 -t $(TARGET_DIR)/var/www-portal/x/ $(THINGINO_PORTAL_PKGDIR)/files/index.cgi
	$(INSTALL) -m 755 -t $(TARGET_DIR)/var/www-portal/x/ $(THINGINO_PORTAL_PKGDIR)/files/portal.cgi
        find $(TARGET_DIR)/var/www-portal/x/ -type f -name *.cgi -exec chmod 755 {} \;

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www/a $(THINGINO_PORTAL_PKGDIR)/files/bootstrap.bundle.min.js
	$(INSTALL) -m 644 -t $(TARGET_DIR)/var/www/a $(THINGINO_PORTAL_PKGDIR)/files/bootstrap.min.css
        find $(TARGET_DIR)/var/www/a/ -type f \( -name "*.css" -o -name "*.ico" -o -name "*.js" -o -name "*.svg" \) -exec gzip {} \;

	ln -sr $(TARGET_DIR)/var/www/a/bootstrap.min.css.gz       $(TARGET_DIR)/var/www-portal/
	ln -sr $(TARGET_DIR)/var/www/a/bootstrap.bundle.min.js.gz $(TARGET_DIR)/var/www-portal/
endef

$(eval $(generic-package))
