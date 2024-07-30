WIFI_SYN43438_VERSION = $(LINUX_VERSION_PROBED)
WIFI_SYN43438_SITE_METHOD = git
WIFI_SYN43438_VERSION=$(shell git ls-remote $(WIFI_SYN43438_SITE) $(WIFI_SYN43438_SITE_BRANCH) | head -1 | cut -f1)
WIFI_SYN43438_SITE = http://github.com/acvigue/bcmdhd

WIFI_SYN43438_MODULE_MAKE_OPTS = \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR) \
        CONFIG_BCMDHD=m \
        CONFIG_BCMDHD_SDIO=y \
        CONFIG_BCMDHD_OOB=y \
        CONFIG_CFG80211=y \
        CONFIG_BCMDHD_AG=y \
        CONFIG_BCMDHD_FW_PATH="/lib/firmware/fw_bcm43438a1.bin" \
        CONFIG_BCMDHD_NVRAM_PATH="/lib/firmware/nv_bcm43438a1.txt"

define WIFI_SYN43438_INSTALL_TARGET_CMDS
        $(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/firmware
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_SYN43438_PKGDIR)/files/fw_bcm43438a1.bin
        $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/firmware $(WIFI_SYN43438_PKGDIR)/files/nv_bcm43438a1.txt
endef

$(eval $(kernel-module))
$(eval $(generic-package))