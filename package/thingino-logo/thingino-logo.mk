THINGINO_LOGO_LICENSE = MIT

define THINGINO_LOGO_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/share/images
	$(INSTALL) -D -m 0644 $(THINGINO_LOGO_PKGDIR)/files/thingino_100x30.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_100x30.bgra
	$(INSTALL) -D -m 0644 $(THINGINO_LOGO_PKGDIR)/files/thingino_210x64.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_210x64.bgra
endef

$(eval $(generic-package))
