WIFI_RTL8188ES_SITE_METHOD = git
WIFI_RTL8188ES_SITE = https://github.com/jwrdegoede/rtl8189es_linux
WIFI_RTL8188ES_VERSION = $(shell git ls-remote $(WIFI_RTL8188ES_SITE) master | head -1 | cut -f1)

WIFI_RTL8188ES_LICENSE = GPL-2.0

WIFI_RTL8188ES_MODULE_MAKE_OPTS = CONFIG_RTL8189ES=m \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
