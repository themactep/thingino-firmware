WIFI_RTL8189FS_SITE_METHOD = git
ifeq ($(LINUX_VERSION_4_4),y)
WIFI_RTL8189FS_SITE = https://github.com/jwrdegoede/rtl8189ES_linux
else
WIFI_RTL8189FS_SITE = https://github.com/openipc/realtek-wlan
endif

WIFI_RTL8189FS_VERSION = $(shell git ls-remote $(WIFI_RTL8189FS_SITE) rtl8189fs | head -1 | cut -f1)

WIFI_RTL8189FS_LICENSE = GPL-2.0
WIFI_RTL8189FS_LICENSE_FILES = COPYING

WIFI_RTL8189FS_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR) \
	KVER=$(LINUX_VERSION_PROBED) \
	CONFIG_RTL8189FS=m
	CONFIG_SDIO_HCI=y

$(eval $(kernel-module))
$(eval $(generic-package))
