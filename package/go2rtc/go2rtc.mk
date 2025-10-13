GO2RTC_SITE_METHOD = git
ifeq ($(BR2_PACKAGE_GO2RTC_MINI),y)
	GO2RTC_SITE = https://github.com/wltechblog/go2rtc-smaller
	GO2RTC_SITE_BRANCH = master
	GO2RTC_VERSION = df95ce39d08f4eae0544f7dc340f8d8ee27a5752
	# $(shell git ls-remote $(GO2RTC_SITE) $(GO2RTC_SITE_BRANCH) | head -1 | cut -f1)
else
	GO2RTC_SITE = https://github.com/AlexxIT/go2rtc
	GO2RTC_SITE_BRANCH = master
	GO2RTC_VERSION = df95ce39d08f4eae0544f7dc340f8d8ee27a5752
	# $(shell git ls-remote $(GO2RTC_SITE) $(GO2RTC_SITE_BRANCH) | head -1 | cut -f1)
endif

GO2RTC_LICENSE = MIT
GO2RTC_LICENSE_FILES = LICENSE

GO2RTC_INSTALL_TARGET = YES

GO2RTC_DEPENDENCIES = host-upx toolchain
GO2RTC_LDFLAGS = -s -w" -gcflags=all="-l -B
GO2RTC_GO_ENV = \
    GOARCH=mipsle \
    CGO_ENABLED=1 \
    CC=$(TARGET_CC) \
    CXX=$(TARGET_CXX) \
    CGO_CFLAGS="$(TARGET_CFLAGS)" \
    CGO_LDFLAGS="$(TARGET_LDFLAGS)"

define GO2RTC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(GO2RTC_PKGDIR)/files/go2rtc.yaml \
		$(TARGET_DIR)/etc/go2rtc.yaml

	$(INSTALL) -D -m 0755 $(GO2RTC_PKGDIR)/files/S97go2rtc \
		$(TARGET_DIR)/etc/init.d/S97go2rtc

	$(INSTALL) -D -m 0755 $(@D)/bin/go2rtc \
		$(TARGET_DIR)/usr/bin/go2rtc

	$(HOST_DIR)/bin/upx --best --lzma $(TARGET_DIR)/usr/bin/go2rtc
endef

define GO2RTC_BUILD_CMDS
    cd $(@D); \
    GOARCH=mipsle \
    CGO_ENABLED=0 \
    $(HOST_DIR)/bin/go build -v \
        -ldflags "-s -w" \
        -gcflags=all="-l -B" \
        -tags "noalsa nov4l2" \
        -modcacherw \
        -trimpath \
        -p $(PARALLEL_JOBS) \
        -buildvcs=false \
        -o $(@D)/bin/go2rtc \
        github.com/AlexxIT/go2rtc/.
endef

$(eval $(golang-package))
