WIFI_ATBM_WIFI_SITE_METHOD = git
WIFI_ATBM_WIFI_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_ATBM_WIFI_SITE_BRANCH = master
WIFI_ATBM_WIFI_VERSION = 5c4dd2c6febaa924a81551f5ce8d3e71c728cc91
# $(shell git ls-remote $(WIFI_ATBM_WIFI_SITE) $(WIFI_ATBM_WIFI_SITE_BRANCH) | head -1 | cut -f1)

WIFI_ATBM_WIFI_LICENSE = GPL-2.0

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

define WIFI_ATBM_WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt
endef

$(eval $(generic-package))
