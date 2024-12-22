define THINGINO_SYSUPGRADE_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_SYSUPGRADE_PKGDIR)/files/gestalt
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_SYSUPGRADE_PKGDIR)/files/sysupgrade
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_SYSUPGRADE_PKGDIR)/files/sysupgrade-stage2
endef

$(eval $(generic-package))
