define THINGINO_DIAG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/thingino-diag \
		$(TARGET_DIR)/usr/sbin/thingino-diag
endef

$(eval $(generic-package))
