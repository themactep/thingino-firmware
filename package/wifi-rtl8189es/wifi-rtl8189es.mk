WIFI_RTL8189ES_SITE_METHOD = git
WIFI_RTL8189ES_SITE = https://github.com/jwrdegoede/rtl8189es_linux.git
WIFI_RTL8189ES_VERSION = $(shell git ls-remote $(WIFI_RTL8189ES_SITE) master | head -1 | cut -f1)

WIFI_RTL8189ES_LICENSE = GPL-2.0

WIFI_RTL8189ES_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR) \
	KVER=$(LINUX_VERSION_PROBED) \
	CONFIG_RTL8189ES=m

$(eval $(kernel-module))
$(eval $(generic-package))
