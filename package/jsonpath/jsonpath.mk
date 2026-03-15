JSONPATH_SITE_METHOD = git
JSONPATH_SITE = https://github.com/openwrt/jsonpath
JSONPATH_SITE_BRANCH = master
JSONPATH_VERSION = e3f6a4160ba2e4806fead60e535e4fba0f8d06be

JSONPATH_LICENSE = ISC, BSD-3-Clause
JSONPATH_DEPENDENCIES = json-c libubox

define JSONPATH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/jsonpath \
		$(TARGET_DIR)/usr/bin/jsonpath
endef

$(eval $(cmake-package))
