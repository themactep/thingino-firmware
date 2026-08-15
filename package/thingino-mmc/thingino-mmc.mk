THINGINO_MMC_SITE_METHOD = local
THINGINO_MMC_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-mmc

# XBurst1 drives the MSC with jzmmc; XBurst2 (T40/T41) uses sdhci-ingenic,
# built as ingenic_sdhci_sdio.ko. S09mmc ships the XBurst1 name, so patch it
# for XBurst2 or the modprobe fails and the card slot never comes up.
ifeq ($(BR2_mips_xburst2),y)
THINGINO_MMC_MODULE = ingenic_sdhci_sdio
else
THINGINO_MMC_MODULE = jzmmc_v12
endif

define THINGINO_MMC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MMC_PKGDIR)/files/S09mmc \
		$(TARGET_DIR)/etc/init.d/S09mmc
	$(SED) 's|^MMC_MODULE=.*|MMC_MODULE="$(THINGINO_MMC_MODULE)"|' \
		$(TARGET_DIR)/etc/init.d/S09mmc

	$(INSTALL) -D -m 0755 $(THINGINO_MMC_PKGDIR)/files/mmc \
		$(TARGET_DIR)/usr/sbin/mmc
endef

$(eval $(generic-package))
