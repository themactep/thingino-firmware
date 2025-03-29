define THINGINO_SYSUPGRADE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_SYSUPGRADE_PKGDIR)/files/gestalt \
		$(TARGET_DIR)/usr/sbin/gestalt

	$(INSTALL) -D -m 0755 $(THINGINO_SYSUPGRADE_PKGDIR)/files/sysupgrade \
		$(TARGET_DIR)/usr/sbin/sysupgrade

	$(INSTALL) -D -m 0755 $(THINGINO_SYSUPGRADE_PKGDIR)/files/sysupgrade-stage2 \
		$(TARGET_DIR)/usr/sbin/sysupgrade-stage2
endef

$(eval $(generic-package))
