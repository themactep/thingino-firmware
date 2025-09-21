THINGINO_DEVSCRIPTS_SITE_METHOD = local
THINGINO_DEVSCRIPTS_SITE = $(BR2_EXTERNAL)/package/thingino-devscripts

define THINGINO_DEVSCRIPTS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_DEVSCRIPTS_PKGDIR)/files/daylightsample \
		$(TARGET_DIR)/usr/sbin/daylightsample

	$(INSTALL) -D -m 0755 $(THINGINO_DEVSCRIPTS_PKGDIR)/files/gpioscan \
		$(TARGET_DIR)/usr/sbin/gpioscan

	$(INSTALL) -D -m 0755 $(THINGINO_DEVSCRIPTS_PKGDIR)/files/speakerseeker \
		$(TARGET_DIR)/usr/sbin/speakerseeker

	$(INSTALL) -D -m 0755 $(THINGINO_DEVSCRIPTS_PKGDIR)/files/ticklemotor \
		$(TARGET_DIR)/usr/sbin/ticklemotor

	$(INSTALL) -D -m 0755 $(THINGINO_DEVSCRIPTS_PKGDIR)/files/ispmem-calc \
		$(TARGET_DIR)/usr/sbin/ispmem-calc

	$(INSTALL) -D -m 0755 $(THINGINO_DEVSCRIPTS_PKGDIR)/files/overlay-backup \
		$(TARGET_DIR)/usr/sbin/overlay-backup

endef

$(eval $(generic-package))
