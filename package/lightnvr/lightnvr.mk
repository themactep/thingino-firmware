LIGHTNVR_SITE_METHOD = git
LIGHTNVR_SITE = https://github.com/opensensor/lightNVR
LIGHTNVR_SITE_BRANCH = main
LIGHTNVR_VERSION = a5e16eeff9705e18d5aaa619f15d019c9bd3dfea

LIGHTNVR_LICENSE = MIT
LIGHTNVR_LICENSE_FILES = COPYING

LIGHTNVR_INSTALL_STAGING = YES

# Dependencies
LIGHTNVR_DEPENDENCIES = thingino-ffmpeg thingino-libcurl sqlite

ifeq ($(BR2_PACKAGE_MBEDTLS),y)
LIGHTNVR_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_THINGINO_WOLFSSL),y)
LIGHTNVR_DEPENDENCIES += thingino-wolfssl
endif

# Enable SOD with dynamic linking and go2rtc, use bundled cJSON
LIGHTNVR_CONF_OPTS = \
	-DENABLE_SOD=ON \
	-DSOD_DYNAMIC_LINK=ON \
	-DENABLE_GO2RTC=ON \
	-DGO2RTC_BINARY_PATH=/bin/go2rtc \
	-DGO2RTC_CONFIG_DIR=/etc/lightnvr/go2rtc \
	-DGO2RTC_API_PORT=1984

# Main application files installation
define LIGHTNVR_INSTALL_APP_FILES
	$(INSTALL) -d $(TARGET_DIR)/var/nvr
	cp -r $(@D)/web/dist $(TARGET_DIR)/var/nvr/web
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/lightnvr
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/lightnvr/go2rtc
	$(INSTALL) -m 644 $(@D)/config/lightnvr.ini $(TARGET_DIR)/etc/lightnvr/lightnvr.ini
	$(INSTALL) -D -m 0755 $(@D)/bin/lightnvr $(TARGET_DIR)/usr/bin/lightnvr
	$(INSTALL) -m 0755 -D $(LIGHTNVR_PKGDIR)/files/S95lightnvr $(TARGET_DIR)/etc/init.d/S95lightnvr
endef

# SOD shared libraries installation - specifically using the src/sod version
define LIGHTNVR_INSTALL_LIBSOD
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 0755 $(@D)/src/sod/libsod.so.1.1.9 $(TARGET_DIR)/usr/lib/
	$(INSTALL) -m 0755 $(@D)/src/sod/libsod.so.1 $(TARGET_DIR)/usr/lib/
	$(INSTALL) -m 0755 $(@D)/src/sod/libsod.so $(TARGET_DIR)/usr/lib/
endef

# The complete target installation command set
define LIGHTNVR_INSTALL_TARGET_CMDS
	$(LIGHTNVR_INSTALL_APP_FILES)
	$(LIGHTNVR_INSTALL_LIBSOD)
endef

$(eval $(cmake-package))
