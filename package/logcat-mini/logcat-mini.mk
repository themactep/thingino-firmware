LOGCAT_MINISITE_METHOD = git
LOGCAT_MINISITE = https://github.com/wltechblog/logcat-mini
LOGCAT_MINIVERSION = $(shell git ls-remote $(LOGCAT_MINISITE) HEAD | head -1 | cut -f1)

LOGCAT_MINILICENSE = GPL-2.0
LOGCAT_MINILICENSE_FILES = COPYING

LOGCAT_MINIINSTALL_STAGING = YES

LOGCAT_MINIDEPENDENCIES = host-upx
define LOGCAT_MINIINSTALL_STAGING_CMDS
        $(HOST_DIR)/bin/upx --best $(@D)/logcat
endef

$(eval $(cmake-package))
