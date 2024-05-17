WIFI_SSV6X5X_SITE_METHOD = git
WIFI_SSV6X5X_SITE = https://github.com/openipc/ssv6x5x
WIFI_SSV6X5X_SITE_BRANCH = master
WIFI_SSV6X5X_VERSION = $(shell git ls-remote $(WIFI_SSV6X5X_SITE) $(WIFI_SSV6X5X_SITE_BRANCH) | head -1 | cut -f1)

WIFI_SSV6X5X_LICENSE = GPL-2.0
WIFI_SSV6X5X_LICENSE_FILES = COPYING

WIFI_SSV6X5X_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
