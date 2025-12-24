THINGINO_WEBUI_MINI_SITE_METHOD = local
THINGINO_WEBUI_MINI_SITE = $(THINGINO_WEBUI_MINI_PKGDIR)/files
THINGINO_WEBUI_MINI_LICENSE = MIT

define THINGINO_WEBUI_MINI_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_MINI_PKGDIR)/files/httpd.conf  $(TARGET_DIR)/etc/httpd.conf
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_MINI_PKGDIR)/files/S50httpd    $(TARGET_DIR)/etc/init.d/S50httpd

	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_MINI_PKGDIR)/files/index.html  $(TARGET_DIR)/var/www/index.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_MINI_PKGDIR)/files/favicon.ico $(TARGET_DIR)/var/www/favicon.ico
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_MINI_PKGDIR)/files/data.json   $(TARGET_DIR)/var/www/data.json
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_MINI_PKGDIR)/files/sse.sh      $(TARGET_DIR)/var/www/x/sse.sh

	ln -s /usr/share/tz.json $(TARGET_DIR)/var/www/tz.json
endef

$(eval $(generic-package))
