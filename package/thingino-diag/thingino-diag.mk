define THINGINO_DIAG_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/thingino-diag
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/soc
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/sensor
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/sensor-info
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/overlay-backup
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/ispmem-calc
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/firstboot
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/usb-role
endef

$(eval $(generic-package))
