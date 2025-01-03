WIFI_ATBM60XX_SITE_METHOD = git
WIFI_ATBM60XX_SITE = https://github.com/gtxaspec/atbm60xx
WIFI_ATBM60XX_SITE_BRANCH = master
WIFI_ATBM60XX_VERSION = 933a3bc2b3e1100ae00831b82132f8ae200a324d
# $(shell git ls-remote $(WIFI_ATBM60XX_SITE) $(WIFI_ATBM60XX_SITE_BRANCH) | head -1 | cut -f1)

WIFI_ATBM60XX_LICENSE = GPL-2.0

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))
define WIFI_ATBM60XX_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/share/atbm60xx_conf
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/share/atbm60xx_conf $(WIFI_ATBM60XX_PKGDIR)/files/*.txt
endef

$(eval $(generic-package))
