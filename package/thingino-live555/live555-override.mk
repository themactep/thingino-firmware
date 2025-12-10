################################################################################
#
# live555 overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_LIVE555),y)

override LIVE555_SITE_METHOD = git
override LIVE555_SITE = https://github.com/themactep/live555
override LIVE555_VERSION = e116665ab4fa57fb6f2353ccf4897cf3f4f5b96b
override LIVE555_SITE_BRANCH = master
override LIVE555_SOURCE = live555-$(LIVE555_VERSION).tar.gz

override LIVE555_CFLAGS += \
	-DALLOW_RTSP_SERVER_PORT_REUSE \
	-DNO_STD_LIB \
	-DNO_OPENSSL

ifeq ($(THINGINO_LIVE555_USE_OPENRTSP),y)
# Install openRTSP helper into the target rootfs.
define THINGINO_LIVE555_INSTALL_OPENRTSP
	$(INSTALL) -D -m 0755 $(@D)/testProgs/openRTSP \
		$(TARGET_DIR)/usr/bin/openRTSP
endef
LIVE555_POST_INSTALL_TARGET_HOOKS += THINGINO_LIVE555_INSTALL_OPENRTSP
endif

endif
