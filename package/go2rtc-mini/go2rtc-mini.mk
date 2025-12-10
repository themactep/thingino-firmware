GO2RTC_MINI_SITE_METHOD = git
GO2RTC_MINI_SITE = https://github.com/wltechblog/go2rtc-smaller
GO2RTC_MINI_SITE_BRANCH = master
GO2RTC_MINI_VERSION = 49b7e2c1b74b9fc4e529d2a1626ab67489eecc7c

GO2RTC_MINI_LICENSE = MIT
GO2RTC_MINI_LICENSE_FILES = LICENSE

GO2RTC_MINI_INSTALL_TARGET = YES

GO2RTC_MINI_DEPENDENCIES = host-upx

# Disable CGO to avoid V4L2/ALSA C dependencies on MIPS
GO2RTC_MINI_GO_ENV = CGO_ENABLED=0 GOARCH=mipsle

# Strip debug symbols (-s -w) for smaller binary
GO2RTC_MINI_LDFLAGS = -s -w

# Disable inlining and bounds checking for smaller binary
GO2RTC_MINI_BUILD_OPTS = -gcflags=all="-l -B"

define GO2RTC_MINI_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(GO2RTC_MINI_PKGDIR)/files/go2rtc.yaml \
		$(TARGET_DIR)/etc/go2rtc.yaml

	$(INSTALL) -D -m 0755 $(GO2RTC_MINI_PKGDIR)/files/S97go2rtc \
		$(TARGET_DIR)/etc/init.d/S97go2rtc

	$(INSTALL) -D -m 0755 $(@D)/bin/go2rtc \
		$(TARGET_DIR)/usr/bin/go2rtc

	$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/go2rtc
endef

$(eval $(golang-package))
