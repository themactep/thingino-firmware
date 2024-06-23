WIFI_BCM43438_VERSION = $(LINUX_VERSION_PROBED)
WIFI_BCM43438_SITE_METHOD = local
WIFI_BCM43438_VERSION=1.0
WIFI_BCM43438_SITE = $(LINUX_DIR)/drivers/net/wireless/bcmdhd_1_141_66
define WIFI_BCM43438_LINUX_CONFIG_FIXUPS
        $(call KCONFIG_SET_OPT,CONFIG_BCMDHD_1_141_66=m)
        $(call KCONFIG_SET_OPT,CONFIG_BCMDHD_1_141_66_SDIO,y)
endef

define WIFI_BCM43438_INSTALL_TARGET_CMDS
        $(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/firmware
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_BCM43438_PKGDIR)/files/fw_bcm43436b0.bin
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_BCM43438_PKGDIR)/files/fw_bcm43438a1.bin
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_BCM43438_PKGDIR)/files/nv_bcm43436b0.txt
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_BCM43438_PKGDIR)/files/nv_bcm43438a1.txt
endef

$(eval $(kernel-module))
$(eval $(generic-package))


