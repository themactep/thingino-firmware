define THINGINO_DIAG_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_DIAG_PKGDIR)/files/thingino-diag
endef

$(eval $(generic-package))
