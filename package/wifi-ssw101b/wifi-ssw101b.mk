WIFI_SSW101B_SITE_METHOD = git
WIFI_SSW101B_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_SSW101B_SITE_BRANCH = main
WIFI_SSW101B_VERSION = $(shell git ls-remote $(WIFI_SSW101B_SITE) $(WIFI_SSW101B_SITE_BRANCH) | head -1 | cut -f1)

SSW101B_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))
