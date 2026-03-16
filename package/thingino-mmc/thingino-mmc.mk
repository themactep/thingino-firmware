THINGINO_MMC_SITE_METHOD = local
THINGINO_MMC_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-mmc

define THINGINO_MMC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MMC_PKGDIR)/files/S09mmc \
		$(TARGET_DIR)/etc/init.d/S09mmc

	$(INSTALL) -D -m 0755 $(THINGINO_MMC_PKGDIR)/files/mmc \
		$(TARGET_DIR)/usr/sbin/mmc
endef

$(eval $(generic-package))
