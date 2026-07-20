THINGINO_PRIVACY_LITE_SITE_METHOD = local
THINGINO_PRIVACY_LITE_SITE = $(THINGINO_PRIVACY_LITE_PKGDIR)

THINGINO_PRIVACY_LITE_DEPENDENCIES += thingino-jct

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
THINGINO_PRIVACY_LITE_DEPENDENCIES += thingino-webui

define THINGINO_PRIVACY_LITE_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(THINGINO_PRIVACY_LITE_PKGDIR)/files/www/config-privacy.html \
		$(TARGET_DIR)/var/www/config-privacy.html
	$(INSTALL) -D -m 0644 $(THINGINO_PRIVACY_LITE_PKGDIR)/files/www/a/privacy.js \
		$(TARGET_DIR)/var/www/a/privacy.js
	$(INSTALL) -D -m 0644 $(THINGINO_PRIVACY_LITE_PKGDIR)/files/privacy.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/privacy.webui.json
endef
endif

define THINGINO_PRIVACY_LITE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_PRIVACY_LITE_PKGDIR)/files/privacy-plugin-lite \
		$(TARGET_DIR)/usr/libexec/thingino/privacy-plugin-lite
	$(THINGINO_PRIVACY_LITE_INSTALL_WWW_CMDS)
endef

$(eval $(generic-package))
