THINGINO_MMC_SITE_METHOD = local
THINGINO_MMC_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-mmc

# XBurst1 drives the MSC with jzmmc; XBurst2 (T40/T41) uses sdhci-ingenic, and
# t32 uses sdhci-jz. The latter two both build as ingenic_sdhci_sdio.ko. S09mmc
# ships the jzmmc name, so patch it for those or the modprobe fails and the card
# slot never comes up. S09mmc also keys the cd_gpio_pin parameter off this name;
# only jzmmc takes it, the sdhci drivers get their pins from platform data.
ifeq ($(KERNEL_VERSION_7),y)
# 7.x uses the mainline drivers: jz4740_mmc on XBurst1, sdhci-ingenic on
# XBurst2 (T40/T41). The vendor jzmmc_v12 name is for 3.10/4.4 only.
ifeq ($(filter t40 t41,$(SOC_FAMILY)),)
THINGINO_MMC_MODULE = jz4740_mmc
else
THINGINO_MMC_MODULE = ingenic_sdhci_sdio
endif
else ifeq ($(filter t32 t40 t41,$(SOC_FAMILY)),)
THINGINO_MMC_MODULE = jzmmc_v12
else
THINGINO_MMC_MODULE = ingenic_sdhci_sdio
endif

define THINGINO_MMC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MMC_PKGDIR)/files/S09mmc \
		$(TARGET_DIR)/etc/init.d/S09mmc
	$(SED) 's|^MMC_MODULE=.*|MMC_MODULE="$(THINGINO_MMC_MODULE)"|' \
		$(TARGET_DIR)/etc/init.d/S09mmc
	$(SED) 's|^MMC_CD_PIN=.*|MMC_CD_PIN="$(MMC_CD_PIN)"|' \
		$(TARGET_DIR)/etc/init.d/S09mmc

	$(INSTALL) -D -m 0755 $(THINGINO_MMC_PKGDIR)/files/mmc \
		$(TARGET_DIR)/usr/sbin/mmc
endef

$(eval $(generic-package))
