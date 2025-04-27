THINGINO_SOUNDS_LICENSE = CC0
THINGINO_SOUNDS_LICENSE_FILES = LICENSE

define THINGINO_SOUNDS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_SOUNDS_PKGDIR)/files/thingino.pcm \
		$(TARGET_DIR)/usr/share/sounds/thingino.pcm

	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
		$(THINGINO_SOUNDS_PKGDIR)/files/th-chime_*.pcm

	if [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/th-doorbell_*.pcm; \
	fi
endef

$(eval $(generic-package))
