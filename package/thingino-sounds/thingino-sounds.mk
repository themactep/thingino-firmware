THINGINO_SOUNDS_LICENSE = CC0
THINGINO_SOUNDS_LICENSE_FILES = LICENSE

define THINGINO_SOUNDS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/sounds
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/sounds $(THINGINO_SOUNDS_PKGDIR)/files/th-chime_*.pcm
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/sounds $(THINGINO_SOUNDS_PKGDIR)/files/thingino.pcm
	if [ "$(BR2_THINGINO_DEVICE_TYPE_DOORBELL)" = "y" ]; then \
		$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/sounds $(THINGINO_SOUNDS_PKGDIR)/files/th-doorbell_*.pcm; \
	fi
endef

$(eval $(generic-package))
