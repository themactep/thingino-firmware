JSONFILTER_SITE_METHOD = git
JSONFILTER_SITE = https://github.com/openwrt/jsonpath
JSONFILTER_SITE_BRANCH = master
JSONFILTER_VERSION = 8a86fb78235b5d7925b762b7b0934517890cc034
# $(shell git ls-remote $(JSONFILTER_SITE) $(JSONFILTER_SITE_BRANCH) | head -1 | cut -f1)

JSONFILTER_LICENSE = ISC, BSD-3-Clause
JSONFILTER_DEPENDENCIES = json-c libubox

define JSONFILTER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/jsonpath \
		$(TARGET_DIR)/usr/bin/jsonfilter
endef

$(eval $(cmake-package))
