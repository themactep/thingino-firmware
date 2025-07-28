THINGINO_STREAMER_SITE_METHOD = git
THINGINO_STREAMER_SITE = https://github.com/themactep/thingino-streamer
THINGINO_STREAMER_SITE_BRANCH = master
#THINGINO_STREAMER_VERSION = 6eab9c0ef6fac8eb80f10ce489bca18295d84729
THINGINO_STREAMER_VERSION = $(shell git ls-remote $(THINGINO_STREAMER_SITE) $(THINGINO_STREAMER_SITE_BRANCH) | head -1 | cut -f1)

THINGINO_STREAMER_GIT_SUBMODULES = YES

THINGINO_STREAMER_DEPENDENCIES = json-c ingenic-lib libschrift
THINGINO_STREAMER_DEPENDENCIES += thingino-opus

THINGINO_STREAMER_CFLAGS += \
	-Os -DHAVE_LIBSCHRIFT=1 \
	-I$(STAGING_DIR)/usr/include

# Add platform and kernel version flags
THINGINO_STREAMER_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION_4),y)
	THINGINO_STREAMER_CFLAGS += -DKERNEL_VERSION_4
endif

# Add libc type flags
ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	THINGINO_STREAMER_CFLAGS += -DLIBC_GLIBC
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	THINGINO_STREAMER_CFLAGS += -DLIBC_UCLIBC
endif

# Add musl shim dependency for musl-based toolchains
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	THINGINO_STREAMER_DEPENDENCIES += ingenic-musl
endif

THINGINO_STREAMER_DEPENDENCIES += host-jq
THINGINO_STREAMER_DEPENDENCIES += libwebsockets

# Add module-specific CFLAGS and LDFLAGS based on enabled features

# Add TLS dependencies based on selection
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL),y)
THINGINO_STREAMER_DEPENDENCIES += openssl
else
# Add NO_OPENSSL flag only if OpenSSL TLS backend is not selected
THINGINO_STREAMER_CFLAGS += -DNO_OPENSSL=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_MBEDTLS),y)
THINGINO_STREAMER_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_AUDIO),y)
THINGINO_STREAMER_DEPENDENCIES += faac libhelix-aac
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_OSD),y)
THINGINO_STREAMER_DEPENDENCIES += libschrift
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_WEBRTC),y)
THINGINO_STREAMER_DEPENDENCIES += libpeer
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_AUDIO),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_AUDIO=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_HTTP),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_HTTP=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_IMAGE_GRAB),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_IMAGE_GRAB=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_IMP_CONTROL),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_IMP_CONTROL=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_METRICS),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_METRICS=1
# Add metrics module LDFLAGS here if needed
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_MOTION),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_MOTION=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_ONVIF),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_ONVIF=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_OSD),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_OSD=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_PHOTOSENSING),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_PHOTOSENSING=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_RTMP_SERVER),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_RTMP_SERVER=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_RTMP_CLIENT),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_RTMP_CLIENT=1
# RTMPS TLS backend selection
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_RTMPS=1 -DRTMPS_BACKEND_OPENSSL=1
endif
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_MBEDTLS),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_RTMPS=1 -DRTMPS_BACKEND_MBEDTLS=1
endif
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_RTSP),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_RTSP=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_RTSPS),y)
THINGINO_STREAMER_CFLAGS += -DENABLE_RTSPS=1
# Reuse RTMPS TLS backend selection for RTSPS
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL),y)
THINGINO_STREAMER_CFLAGS += -DRTSPS_BACKEND_OPENSSL=1
endif
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_MBEDTLS),y)
THINGINO_STREAMER_CFLAGS += -DRTSPS_BACKEND_MBEDTLS=1
endif
endif

# Base LDFLAGS
THINGINO_STREAMER_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

# Add module-specific LDFLAGS
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_OSD),y)
THINGINO_STREAMER_LDFLAGS += -lschrift
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_WEBRTC),y)
THINGINO_STREAMER_CFLAGS += \
	-DWEBRTC_ENABLED=1 \
	-DLIBPEER_AVAILABLE=1 \
	-I$(STAGING_DIR)/usr/include
THINGINO_STREAMER_LDFLAGS += -lpeer -lsrtp2 -lusrsctp
endif

# Add TLS/SSL library flags
ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL),y)
THINGINO_STREAMER_LDFLAGS += -lssl -lcrypto
endif

ifeq ($(BR2_PACKAGE_THINGINO_STREAMER_TLS_MBEDTLS),y)
THINGINO_STREAMER_LDFLAGS += -lmbedtls -lmbedx509 -lmbedcrypto
endif

define THINGINO_STREAMER_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="$(THINGINO_STREAMER_CFLAGS)" \
		LDFLAGS="$(THINGINO_STREAMER_LDFLAGS)" \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_AUDIO),ENABLE_AUDIO=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_HTTP),ENABLE_HTTP=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_IMAGE_GRAB),ENABLE_IMAGE_GRAB=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_IMP_CONTROL),ENABLE_IMP_CONTROL=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_METRICS),ENABLE_METRICS=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_MOTION),ENABLE_MOTION=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_ONVIF),ENABLE_ONVIF=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_OSD),ENABLE_OSD=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_PHOTOSENSING),ENABLE_PHOTOSENSING=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_RTSP),ENABLE_RTSP=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_RTSPS),ENABLE_RTSPS=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_RTMP_SERVER),ENABLE_RTMP_SERVER=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_RTMP_CLIENT),ENABLE_RTMP_CLIENT=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL),RTMPS_BACKEND_OPENSSL=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_TLS_MBEDTLS),RTMPS_BACKEND_MBEDTLS=1,) \
		$(if $(BR2_PACKAGE_THINGINO_STREAMER_WEBRTC),WEBRTC_ENABLED=1,) \
		-C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

define THINGINO_STREAMER_INSTALL_TARGET_CMDS
	# Install the streamer binary
	$(INSTALL) -D -m 0755 $(@D)/bin/streamer \
		$(TARGET_DIR)/usr/bin/streamer

	# Install the JSON configuration file
	$(INSTALL) -D -m 0644 $(@D)/res/streamer.json \
		$(TARGET_DIR)/etc/streamer.json

	# Install module configs if they exist
	if [ -d $(@D)/res/config ]; then \
		mkdir -p $(TARGET_DIR)/etc/streamer.d && \
		cp -r $(@D)/res/config/* $(TARGET_DIR)/etc/streamer.d/; \
	fi

	# Install watchdog service
	$(INSTALL) -D -m 0755 $(THINGINO_STREAMER_PKGDIR)/files/S94streamer-watchdog \
		$(TARGET_DIR)/etc/init.d/S94streamer-watchdog

	# Install streamer service
	$(INSTALL) -D -m 0755 $(THINGINO_STREAMER_PKGDIR)/files/S95streamer \
		$(TARGET_DIR)/etc/init.d/S95streamer

	# Install watchdog configuration
	$(INSTALL) -D -m 0644 $(THINGINO_STREAMER_PKGDIR)/files/configs/streamer-watchdog.conf \
		$(TARGET_DIR)/etc/default/streamer-watchdog

	# Install default font
	$(INSTALL) -D -m 0644 $(@D)/res/default.ttf \
		$(TARGET_DIR)/usr/share/fonts/default.ttf

	# Install logos
	$(INSTALL) -D -m 0644 $(@D)/res/logo_100x30.bgra \
		$(TARGET_DIR)/usr/share/images/logo_100x30.bgra

	$(INSTALL) -D -m 0644 $(@D)/res/logo_224x60.bgra \
		$(TARGET_DIR)/usr/share/images/logo_224x60.bgra

	# Install SSL certificate generation script
	$(INSTALL) -D -m 0755 $(THINGINO_STREAMER_PKGDIR)/files/generate-ssl-certs.sh \
		$(TARGET_DIR)/usr/bin/generate-ssl-certs.sh
endef

# Post-install hook to generate SSL certificates for TLS-enabled builds
define THINGINO_STREAMER_POST_INSTALL_TARGET_HOOKS_CMD
	# Generate SSL certificates if TLS support is enabled
	if [ "$(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL)" = "y" ]; then \
		echo "Generating SSL certificates for Thingino Streamer..."; \
		mkdir -p $(TARGET_DIR)/etc/ssl/certs $(TARGET_DIR)/etc/ssl/private; \
		if [ "$(BR2_PACKAGE_THINGINO_STREAMER_TLS_OPENSSL)" = "y" ]; then \
			$(HOST_DIR)/bin/openssl req -x509 -newkey rsa:2048 \
				-keyout $(TARGET_DIR)/etc/ssl/private/rtsp-server.key \
				-out $(TARGET_DIR)/etc/ssl/certs/rtsp-server.crt \
				-days 3650 -nodes \
				-subj "/C=US/ST=State/L=City/O=Thingino/CN=camera.local" \
				2>/dev/null || true; \
			chmod 600 $(TARGET_DIR)/etc/ssl/private/rtsp-server.key 2>/dev/null || true; \
			chmod 644 $(TARGET_DIR)/etc/ssl/certs/rtsp-server.crt 2>/dev/null || true; \
			echo "SSL certificates generated at:"; \
			echo "  Certificate: /etc/ssl/certs/rtsp-server.crt"; \
			echo "  Private Key: /etc/ssl/private/rtsp-server.key"; \
		fi; \
	fi
endef

THINGINO_STREAMER_POST_INSTALL_TARGET_HOOKS += THINGINO_STREAMER_POST_INSTALL_TARGET_HOOKS_CMD

$(eval $(generic-package))
