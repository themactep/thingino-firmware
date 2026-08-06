THINGINO_MCU_WDT_SITE_METHOD = local
THINGINO_MCU_WDT_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-mcu-wdt
THINGINO_MCU_WDT_VERSION = local
THINGINO_MCU_WDT_LICENSE = proprietary (vendor binary, redistributed as extracted from stock firmware)
THINGINO_MCU_WDT_DEPENDENCIES = json-c

define THINGINO_MCU_WDT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MCU_WDT_PKGDIR)/files/mcu_test \
		$(TARGET_DIR)/usr/bin/mcu_test
	$(INSTALL) -D -m 0755 $(THINGINO_MCU_WDT_PKGDIR)/files/libcommon.so \
		$(TARGET_DIR)/usr/lib/libcommon.so
	$(INSTALL) -D -m 0755 $(THINGINO_MCU_WDT_PKGDIR)/files/S00mcuwdt \
		$(TARGET_DIR)/etc/init.d/S00mcuwdt
	$(INSTALL) -D -m 0755 $(THINGINO_MCU_WDT_PKGDIR)/files/S01ltepower \
		$(TARGET_DIR)/etc/init.d/S01ltepower
endef

$(eval $(generic-package))
