THINGINO_FONTS_LICENSE = MIT
THINGINO_FONTS_LICENSE_FILES = LICENSE

define THINGINO_FONTS_EXTRACT_CMDS
	cp $(THINGINO_FONTS_PKGDIR)/files/* $(@D)/
endef

define THINGINO_FONTS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/fonts/
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/fonts/ \
		$(@D)/*.ttf
endef

$(eval $(generic-package))
