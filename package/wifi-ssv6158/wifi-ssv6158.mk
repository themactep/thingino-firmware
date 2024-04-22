WIFI_SSV6158_SITE_METHOD = git
WIFI_SSV6158_SITE = https://github.com/wltechblog/wifi-ssv6158
WIFI_SSV6158_VERSION = $(shell git ls-remote $(WIFI_SSV6158_SITE) HEAD | head -1 | cut -f1)

WIFI_SSV6158_LICENSE = GPL-2.0
WIFI_SSV6158_LICENSE_FILES = COPYING

WIFI_SSV6158_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
