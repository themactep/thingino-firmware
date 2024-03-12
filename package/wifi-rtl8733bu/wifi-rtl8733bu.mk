WIFI_RTL8733BU_SITE_METHOD = git
WIFI_RTL8733BU_SITE = https://github.com/openipc/realtek-wlan
WIFI_RTL8733BU_VERSION = $(shell git ls-remote $(WIFI_RTL8733BU_SITE) rtl8733bu | head -1 | cut -f1)

WIFI_RTL8733BU_LICENSE = GPL-2.0
WIFI_RTL8733BU_LICENSE_FILES = COPYING

WIFI_RTL8733BU_MODULE_MAKE_OPTS = \
	CONFIG_RTL8733BU=m \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
