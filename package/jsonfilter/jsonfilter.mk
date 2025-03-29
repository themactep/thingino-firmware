JSONFILTER_SITE_METHOD = git
JSONFILTER_SITE = https://github.com/openwrt/jsonpath
JSONFILTER_SITE_BRANCH = master
JSONFILTER_VERSION = 594cfa86469c005972ba750614f5b3f1af84d0f6
# $(shell git ls-remote $(JSONFILTER_SITE) $(JSONFILTER_SITE_BRANCH) | head -1 | cut -f1)

JSONFILTER_LICENSE = ISC, BSD-3-Clause
JSONFILTER_DEPENDENCIES = json-c libubox

define JSONFILTER_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/jsonpath \
		$(TARGET_DIR)/usr/bin/jsonfilter
endef

$(eval $(cmake-package))
