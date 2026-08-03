THINGINO_MCU_WDT_SITE_METHOD = local
THINGINO_MCU_WDT_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-mcu-wdt
THINGINO_MCU_WDT_VERSION = local
THINGINO_MCU_WDT_LICENSE = proprietary (vendor binary, redistributed as extracted from stock firmware)

define THINGINO_MCU_WDT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MCU_WDT_PKGDIR)/files/disable_mcu_wdt \
		$(TARGET_DIR)/usr/bin/disable_mcu_wdt
	$(INSTALL) -D -m 0755 $(THINGINO_MCU_WDT_PKGDIR)/files/F00a_mcuwdt \
		$(TARGET_DIR)/etc/init.d/F00a_mcuwdt
endef

$(eval $(generic-package))
