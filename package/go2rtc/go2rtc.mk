################################################################################
#
# go2rtc
#
################################################################################

GO2RTC_SITE_METHOD = git
GO2RTC_SITE = https://github.com/AlexxIT/go2rtc
GO2RTC_VERSION = $(shell git ls-remote $(GO2RTC_SITE) HEAD | head -1 | cut -f1)

GO2RTC_LICENSE = MIT
GO2RTC_LICENSE_FILES = LICENSE

GO2RTC_INSTALL_TARGET = YES

GO2RTC_DEPENDENCIES = host-go host-upx
GO2RTC_GO_ENV = GOARCH=mipsle
GO2RTC_LDFLAGS = -s -w

define GO2RTC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/go2rtc $(TARGET_DIR)/usr/bin/go2rtc
	$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/go2rtc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/ $(GO2RTC_PKGDIR)/files/go2rtc.yaml
endef

$(eval $(golang-package))
