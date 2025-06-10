THINGINO_PROVISION_SITE_METHOD = local
THINGINO_PROVISION_SITE = $(THINGINO_PROVISION_PKGDIR)

define THINGINO_PROVISION_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_PROVISION_PKGDIR)/files/S98provision \
		$(TARGET_DIR)/etc/init.d/S98provision
	$(INSTALL) -D -m 0755 $(THINGINO_PROVISION_PKGDIR)/files/provision \
		$(TARGET_DIR)/usr/share/udhcpc/default.script.d/provision
endef

$(eval $(generic-package))
