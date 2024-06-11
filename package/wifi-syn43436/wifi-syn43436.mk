WIFI_SYN43436_VERSION = $(LINUX_VERSION_PROBED)
WIFI_SYN43436_SITE_METHOD = git
WIFI_SYN43436_VERSION=$(shell git ls-remote $(WIFI_SYN43436_SITE) $(WIFI_SYN43436_SITE_BRANCH) | head -1 | cut -f1)
WIFI_SYN43436_SITE = http://github.com/acvigue/bcmdhd

WIFI_SYN43436_MODULE_MAKE_OPTS = \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR) \
        CONFIG_BCMDHD=m \
        CONFIG_BCMDHD_SDIO=y \
        CONFIG_BCMDHD_OOB=y \
        CONFIG_CFG80211=y \
        CONFIG_BCMDHD_AG=y

define WIFI_SYN43436_INSTALL_TARGET_CMDS
        $(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/firmware
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_SYN43436_PKGDIR)/files/fw_bcm43436b0.bin
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_SYN43436_PKGDIR)/files/nv_bcm43436b0.txt
endef

$(eval $(kernel-module))
$(eval $(generic-package))