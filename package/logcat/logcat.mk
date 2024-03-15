LOGCAT_SITE_METHOD = git
LOGCAT_SITE = https://github.com/wltechblog/logcat-mini
LOGCAT_VERSION = $(shell git ls-remote $(LOGCAT_SITE) HEAD | head -1 | cut -f1)

LOGCAT_LICENSE = MIT
LOGCAT_LICENSE_FILES = LICENSE

LOGCAT_INSTALL_STAGING = YES

LOGCAT_DEPENDENCIES = host-upx
define LOGCAT_INSTALL_STAGING_CMDS
        $(HOST_DIR)/bin/upx --best $(@D)/logcat
endef

$(eval $(cmake-package))
