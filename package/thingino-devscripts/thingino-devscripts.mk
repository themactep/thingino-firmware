define THINGINO_DEVSCRIPTS_INSTALL_TARGET_CMDS
        $(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/sbin
        $(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DEVSCRIPTS_PKGDIR)/files/daylightsample
        $(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DEVSCRIPTS_PKGDIR)/files/gpioscan
        $(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DEVSCRIPTS_PKGDIR)/files/ticklemotor
        $(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DEVSCRIPTS_PKGDIR)/files/overlay-backup
endef

$(eval $(generic-package))
