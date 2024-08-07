THINGINO_SOUNDS_LICENSE = CC0
THINGINO_SOUNDS_LICENSE_FILES = LICENSE

define THINGINO_SOUNDS_EXTRACT_CMDS
	cp $(THINGINO_SOUNDS_PKGDIR)/files/* $(@D)/
endef

define THINGINO_SOUNDS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/sounds
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/sounds $(@D)/th-chime_*.pcm
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/sounds $(@D)/thingino.pcm
endef


ifeq ($(BR2_THINGINO_DEVICE_TYPE_DOORBELL),y)
define THINGINO_SOUNDS_INSTALL_DOORBELL_FILES
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/sounds $(@D)/th-doorbell_*
endef

THINGINO_SOUNDS_INSTALL_TARGET_CMDS += THINGINO_SOUNDS_INSTALL_DOORBELL_FILES
endif

$(eval $(generic-package))
