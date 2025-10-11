JSONPATH_SITE_METHOD = git
JSONPATH_SITE = https://github.com/openwrt/jsonpath
JSONPATH_SITE_BRANCH = master
JSONPATH_VERSION = f4fe702d0e8d9f8704b42f5d5c10950470ada231

JSONPATH_LICENSE = ISC, BSD-3-Clause
JSONPATH_DEPENDENCIES = json-c libubox

define JSONPATH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/jsonpath \
		$(TARGET_DIR)/usr/bin/jsonpath
endef

$(eval $(cmake-package))
