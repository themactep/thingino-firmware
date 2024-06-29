THINGINO_WEBUI_SITE_METHOD = local
THINGINO_WEBUI_SITE = $(THINGINO_WEBUI_PKGDIR)/files
THINGINO_WEBUI_LICENSE = MIT
THINGINO_WEBUI_LICENSE_FILES = LICENSE

define THINGINO_WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(THINGINO_WEBUI_PKGDIR)/files/etc/httpd.conf

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(THINGINO_WEBUI_PKGDIR)/files/etc/init.d/S50httpd

	if grep -q "^BR2_THINGINO_DEV_PACKAGES=y" $(BR2_CONFIG); then \
		$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(THINGINO_WEBUI_PKGDIR)/files/etc/init.d/S44devmounts; \
	fi

	$(INSTALL) -m 755 -d $(TARGET_DIR)/var
	cp -rv $(THINGINO_WEBUI_PKGDIR)/files/var/www $(TARGET_DIR)/var/
endef

$(eval $(generic-package))
