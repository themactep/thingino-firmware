GO2RTC_SITE_METHOD = git
ifeq ($(BR2_PACKAGE_GO2RTC_MINI),y)
	GO2RTC_SITE = https://github.com/wltechblog/go2rtc-smaller
	GO2RTC_SITE_BRANCH = master
	GO2RTC_VERSION = 49b7e2c1b74b9fc4e529d2a1626ab67489eecc7c
	# $(shell git ls-remote $(GO2RTC_SITE) $(GO2RTC_SITE_BRANCH) | head -1 | cut -f1)
else
	GO2RTC_SITE = https://github.com/AlexxIT/go2rtc
	GO2RTC_SITE_BRANCH = master
	GO2RTC_VERSION = fa580c516efa95770be2137855c3c3cf19b8092b
	# $(shell git ls-remote $(GO2RTC_SITE) $(GO2RTC_SITE_BRANCH) | head -1 | cut -f1)
endif

GO2RTC_LICENSE = MIT
GO2RTC_LICENSE_FILES = LICENSE

GO2RTC_INSTALL_TARGET = YES

GO2RTC_DEPENDENCIES = host-upx
GO2RTC_GO_ENV = GOARCH=mipsle
GO2RTC_LDFLAGS = -s -w" -gcflags=all="-l -B

define GO2RTC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(GO2RTC_PKGDIR)/files/go2rtc.yaml \
		$(TARGET_DIR)/etc/go2rtc.yaml

	$(INSTALL) -D -m 0755 $(GO2RTC_PKGDIR)/files/S97go2rtc \
		$(TARGET_DIR)/etc/init.d/S97go2rtc

	$(INSTALL) -D -m 0755 $(@D)/bin/go2rtc \
		$(TARGET_DIR)/usr/bin/go2rtc

	$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/go2rtc
endef

$(eval $(golang-package))
