THINGINO_SYSUPGRADE_SITE_METHOD = local
THINGINO_SYSUPGRADE_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-sysupgrade

define THINGINO_SYSUPGRADE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_SYSUPGRADE_PKGDIR)/files/gestalt \
		$(TARGET_DIR)/usr/sbin/gestalt

	$(INSTALL) -D -m 0755 $(THINGINO_SYSUPGRADE_PKGDIR)/files/sysupgrade \
		$(TARGET_DIR)/usr/sbin/sysupgrade

	$(INSTALL) -D -m 0755 $(THINGINO_SYSUPGRADE_PKGDIR)/files/sysupgrade-stage2 \
		$(TARGET_DIR)/usr/sbin/sysupgrade-stage2

	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_THINGINO_PATH)/scripts/cfg-backup.sh \
		$(TARGET_DIR)/usr/sbin/cfg-backup
endef

$(eval $(generic-package))
