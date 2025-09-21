THINGINO_SOUNDS_SITE_METHOD = local
THINGINO_SOUNDS_SITE = $(BR2_EXTERNAL)/package/thingino-sounds
THINGINO_SOUNDS_LICENSE = CC0
THINGINO_SOUNDS_LICENSE_FILES = LICENSE

define THINGINO_SOUNDS_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/share/sounds

	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
		$(THINGINO_SOUNDS_PKGDIR)/files/th-chime_*.pcm

	if [ "$(BR2_PACKAGE_THINGINO_SOUNDS_STARTUP)" = "y" ]; then \
		$(INSTALL) -m 0644 $(THINGINO_SOUNDS_PKGDIR)/files/thingino.pcm \
			$(TARGET_DIR)/usr/share/sounds/thingino.pcm; \
	fi

	if [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/th-doorbell_*.pcm; \
	fi
endef

$(eval $(generic-package))
