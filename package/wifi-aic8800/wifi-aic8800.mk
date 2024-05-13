WIFI_AIC8800_SITE_METHOD = git
WIFI_AIC8800_SITE = https://github.com/openipc/aic8800
WIFI_AIC8800_SITE_BRANCH = master
WIFI_AIC8800_VERSION = $(shell git ls-remote $(WIFI_AIC8800_SITE) $(WIFI_AIC8800_SITE_BRANCH) | head -1 | cut -f1)

WIFI_AIC8800_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))
