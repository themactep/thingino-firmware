GO2RTC_VERSION = 1.9.12
GO2RTC_SITE = $(call github,AlexxIT,go2rtc,v$(GO2RTC_VERSION))

GO2RTC_LICENSE = MIT
GO2RTC_LICENSE_FILES = LICENSE

GO2RTC_INSTALL_TARGET = YES

GO2RTC_DEPENDENCIES = host-upx host-go

# Disable CGO to avoid V4L2/ALSA C dependencies on MIPS
GO2RTC_GO_ENV = CGO_ENABLED=0 GOARCH=mipsle

# Strip debug symbols (-s -w) for smaller binary
GO2RTC_LDFLAGS = -s -w

# Disable inlining and bounds checking for smaller binary
GO2RTC_BUILD_OPTS = -gcflags=all="-l -B"

define GO2RTC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(GO2RTC_PKGDIR)/files/go2rtc.yaml \
		$(TARGET_DIR)/etc/go2rtc.yaml

	$(if $(filter y,$(BR2_PACKAGE_LIGHTNVR)),,$(INSTALL) -D -m 0755 $(GO2RTC_PKGDIR)/files/S97go2rtc $(TARGET_DIR)/etc/init.d/S97go2rtc)

	$(INSTALL) -D -m 0755 $(@D)/bin/go2rtc \
		$(TARGET_DIR)/usr/bin/go2rtc

	$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/go2rtc
endef

$(eval $(golang-package))
