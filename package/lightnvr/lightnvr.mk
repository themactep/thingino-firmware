LIGHTNVR_SITE_METHOD = git
LIGHTNVR_SITE = https://github.com/opensensor/lightNVR
LIGHTNVR_SITE_BRANCH = main
LIGHTNVR_VERSION = 5b75d6655907bf29e5830c02440809460a3f0928

LIGHTNVR_LICENSE = MIT
LIGHTNVR_LICENSE_FILES = COPYING

LIGHTNVR_INSTALL_STAGING = YES

# Dependencies
LIGHTNVR_DEPENDENCIES = thingino-ffmpeg thingino-libcurl sqlite host-nodejs cjson
HOST_LIGHTNVR_DEPENDENCIES = host-nodejs

ifeq ($(BR2_PACKAGE_MBEDTLS),y)
LIGHTNVR_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_WOLFSSL),y)
LIGHTNVR_DEPENDENCIES += wolfssl
endif

# Enable SOD with dynamic linking and go2rtc, use bundled cJSON
LIGHTNVR_CONF_OPTS = \
	-DENABLE_SOD=ON \
	-DSOD_DYNAMIC_LINK=ON \
	-DENABLE_GO2RTC=ON \
	-DGO2RTC_BINARY_PATH=/bin/go2rtc \
	-DGO2RTC_CONFIG_DIR=/etc/lightnvr/go2rtc \
	-DGO2RTC_API_PORT=1984

# Build web assets before CMake configuration
# Web assets are no longer checked into git, so we build them here
define LIGHTNVR_BUILD_WEB_ASSETS
	@echo "Building LightNVR web assets..."
	cd $(@D)/web && \
		export PATH=$(HOST_DIR)/bin/:$$PATH && \
		$(HOST_DIR)/bin/npm ci --production=false && \
		$(HOST_DIR)/bin/npm run build
	@echo "Web assets built successfully"
endef

LIGHTNVR_PRE_BUILD_HOOKS += LIGHTNVR_BUILD_WEB_ASSETS

# Main application files installation - only gzip assets for space savings
define LIGHTNVR_INSTALL_APP_FILES
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/lib/lightnvr
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/lib/lightnvr/web
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/lib/lightnvr/web/assets
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/lib/lightnvr/web/css
	$(INSTALL) -m 755 -d $(TARGET_DIR)/var/lib/lightnvr/web/img
	# Copy only gzip-compressed JS and CSS files (saves ~70% space)
	cp $(@D)/web/dist/assets/*.gz $(TARGET_DIR)/var/lib/lightnvr/web/assets/
	cp $(@D)/web/dist/css/*.gz $(TARGET_DIR)/var/lib/lightnvr/web/css/
	# Copy HTML files (both compressed and uncompressed for initial load)
	cp $(@D)/web/dist/*.html $(TARGET_DIR)/var/lib/lightnvr/web/
	cp $(@D)/web/dist/*.html.gz $(TARGET_DIR)/var/lib/lightnvr/web/
	# Copy images and other static assets
	-cp -r $(@D)/web/dist/img/* $(TARGET_DIR)/var/lib/lightnvr/web/img/ 2>/dev/null || true
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/lightnvr
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/lightnvr/go2rtc
	$(INSTALL) -m 644 $(LIGHTNVR_PKGDIR)/files/lightnvr.ini $(TARGET_DIR)/etc/lightnvr/lightnvr.ini
	$(INSTALL) -m 755 -d $(TARGET_DIR)/opt/lightnvr
	$(INSTALL) -m 755 -d $(TARGET_DIR)/opt/lightnvr/recordings
	$(INSTALL) -m 755 -d $(TARGET_DIR)/opt/lightnvr/recordings/mp4
	$(INSTALL) -m 755 -d $(TARGET_DIR)/opt/lightnvr/database
	$(INSTALL) -m 755 -d $(TARGET_DIR)/opt/lightnvr/models
	$(INSTALL) -m 0755 -D $(@D)/bin/lightnvr $(TARGET_DIR)/usr/bin/lightnvr
	$(INSTALL) -m 0755 -D $(LIGHTNVR_PKGDIR)/files/S95lightnvr $(TARGET_DIR)/etc/init.d/S95lightnvr
endef

# SOD shared libraries installation - specifically using the src/sod version
define LIGHTNVR_INSTALL_LIBSOD
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 0755 $(@D)/src/sod/libsod.so.1.1.9 $(TARGET_DIR)/usr/lib/
	ln -s libsod.so.1.1.9 $(TARGET_DIR)/usr/lib/libsod.so.1
	ln -s libsod.so.1.1.9 $(TARGET_DIR)/usr/lib/libsod.so
endef

# The complete target installation command set
define LIGHTNVR_INSTALL_TARGET_CMDS
	$(LIGHTNVR_INSTALL_APP_FILES)
	$(LIGHTNVR_INSTALL_LIBSOD)
endef

$(eval $(cmake-package))
