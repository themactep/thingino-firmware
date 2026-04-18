STRERO_SITE_METHOD = git
STRERO_SITE = https://github.com/themactep/strero
STRERO_SITE_BRANCH = master
STRERO_VERSION = a91cd5251ce300e7c6cb1106b5c5a9d8ea021350

STRERO_GIT_SUBMODULES = YES

STRERO_DEPENDENCIES = thingino-jct ingenic-lib libschrift
STRERO_DEPENDENCIES += opus

STRERO_CFLAGS += \
	-Os -DHAVE_LIBSCHRIFT=1 \
	-I$(STAGING_DIR)/usr/include

# Add platform and kernel version flags
STRERO_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION),3.10.14)
	STRERO_CFLAGS += -DKERNEL_VERSION_4
endif

# ISP VPU Direct Connect (IVDC): tell encoder to use ISP direct_mode DMA path
ifeq ($(ISP_DIRECT_MODE),direct_mode=1)
STRERO_CFLAGS += -DISP_DIRECT_MODE=1
endif

# Add libc type flags
ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	STRERO_CFLAGS += -DLIBC_GLIBC
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	STRERO_CFLAGS += -DLIBC_UCLIBC
endif

# Add musl shim dependency for musl-based toolchains
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	STRERO_DEPENDENCIES += ingenic-musl
endif

STRERO_DEPENDENCIES += host-jq
STRERO_DEPENDENCIES += libwebsockets

# Add module-specific CFLAGS and LDFLAGS based on enabled features

# Add TLS dependencies based on selection
ifeq ($(BR2_PACKAGE_STRERO_TLS_OPENSSL),y)
STRERO_DEPENDENCIES += openssl
else
# Add NO_OPENSSL flag only if OpenSSL TLS backend is not selected
STRERO_CFLAGS += -DNO_OPENSSL=1
endif

ifeq ($(BR2_PACKAGE_STRERO_TLS_MBEDTLS),y)
STRERO_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_STRERO_AUDIO),y)
STRERO_DEPENDENCIES += faac libhelix-aac
endif

ifeq ($(BR2_PACKAGE_STRERO_OSD),y)
STRERO_DEPENDENCIES += libschrift
endif

ifeq ($(BR2_PACKAGE_STRERO_WEBRTC),y)
STRERO_DEPENDENCIES += libpeer
endif

ifeq ($(BR2_PACKAGE_STRERO_AUDIO),y)
STRERO_CFLAGS += -DENABLE_AUDIO=1
endif

ifeq ($(BR2_PACKAGE_STRERO_HTTP),y)
STRERO_CFLAGS += -DENABLE_HTTP=1
endif

ifeq ($(BR2_PACKAGE_STRERO_IMAGE_GRAB),y)
STRERO_CFLAGS += -DENABLE_IMAGE_GRAB=1
endif

ifeq ($(BR2_PACKAGE_STRERO_IMP_CONTROL),y)
STRERO_CFLAGS += -DENABLE_IMP_CONTROL=1
endif

ifeq ($(BR2_PACKAGE_STRERO_METRICS),y)
STRERO_CFLAGS += -DENABLE_METRICS=1
# Add metrics module LDFLAGS here if needed
endif

ifeq ($(BR2_PACKAGE_STRERO_MOTION),y)
STRERO_CFLAGS += -DENABLE_MOTION=1
endif

ifeq ($(BR2_PACKAGE_STRERO_ONVIF),y)
STRERO_CFLAGS += -DENABLE_ONVIF=1
endif

ifeq ($(BR2_PACKAGE_STRERO_OSD),y)
STRERO_CFLAGS += -DENABLE_OSD=1
endif

ifeq ($(BR2_PACKAGE_STRERO_PHOTOSENSING),y)
STRERO_CFLAGS += -DENABLE_PHOTOSENSING=1
endif

ifeq ($(BR2_PACKAGE_STRERO_RTMP_SERVER),y)
STRERO_CFLAGS += -DENABLE_RTMP_SERVER=1
endif

ifeq ($(BR2_PACKAGE_STRERO_RTMP_CLIENT),y)
STRERO_CFLAGS += -DENABLE_RTMP_CLIENT=1
# RTMPS TLS backend selection
ifeq ($(BR2_PACKAGE_STRERO_TLS_OPENSSL),y)
STRERO_CFLAGS += -DENABLE_RTMPS=1 -DRTMPS_BACKEND_OPENSSL=1
endif
ifeq ($(BR2_PACKAGE_STRERO_TLS_MBEDTLS),y)
STRERO_CFLAGS += -DENABLE_RTMPS=1 -DRTMPS_BACKEND_MBEDTLS=1
endif
endif

ifeq ($(BR2_PACKAGE_STRERO_RTSP),y)
STRERO_CFLAGS += -DENABLE_RTSP=1
endif

ifeq ($(BR2_PACKAGE_STRERO_RTSPS),y)
STRERO_CFLAGS += -DENABLE_RTSPS=1
# Reuse RTMPS TLS backend selection for RTSPS
ifeq ($(BR2_PACKAGE_STRERO_TLS_OPENSSL),y)
STRERO_CFLAGS += -DRTSPS_BACKEND_OPENSSL=1
endif
ifeq ($(BR2_PACKAGE_STRERO_TLS_MBEDTLS),y)
STRERO_CFLAGS += -DRTSPS_BACKEND_MBEDTLS=1
endif
endif

# Base LDFLAGS
STRERO_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

# Add module-specific LDFLAGS
ifeq ($(BR2_PACKAGE_STRERO_OSD),y)
STRERO_LDFLAGS += -lschrift
endif

ifeq ($(BR2_PACKAGE_STRERO_WEBRTC),y)
STRERO_CFLAGS += \
	-DWEBRTC_ENABLED=1 \
	-DLIBPEER_AVAILABLE=1 \
	-I$(STAGING_DIR)/usr/include
STRERO_LDFLAGS += -lpeer -lsrtp2 -lusrsctp
endif

# Add TLS/SSL library flags
ifeq ($(BR2_PACKAGE_STRERO_TLS_OPENSSL),y)
STRERO_LDFLAGS += -lssl -lcrypto
endif

ifeq ($(BR2_PACKAGE_STRERO_TLS_MBEDTLS),y)
STRERO_LDFLAGS += -lmbedtls -lmbedx509 -lmbedcrypto
endif

define STRERO_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="$(STRERO_CFLAGS)" \
		LDFLAGS="$(STRERO_LDFLAGS)" \
		$(if $(BR2_PACKAGE_STRERO_AUDIO),ENABLE_AUDIO=1,) \
		$(if $(BR2_PACKAGE_STRERO_HTTP),ENABLE_HTTP=1,) \
		$(if $(BR2_PACKAGE_STRERO_IMAGE_GRAB),ENABLE_IMAGE_GRAB=1,) \
		$(if $(BR2_PACKAGE_STRERO_IMP_CONTROL),ENABLE_IMP_CONTROL=1,) \
		$(if $(BR2_PACKAGE_STRERO_METRICS),ENABLE_METRICS=1,) \
		$(if $(BR2_PACKAGE_STRERO_MOTION),ENABLE_MOTION=1,) \
		$(if $(BR2_PACKAGE_STRERO_ONVIF),ENABLE_ONVIF=1,) \
		$(if $(BR2_PACKAGE_STRERO_OSD),ENABLE_OSD=1,) \
		$(if $(BR2_PACKAGE_STRERO_PHOTOSENSING),ENABLE_PHOTOSENSING=1,) \
		$(if $(BR2_PACKAGE_STRERO_RTSP),ENABLE_RTSP=1,) \
		$(if $(BR2_PACKAGE_STRERO_RTSPS),ENABLE_RTSPS=1,) \
		$(if $(BR2_PACKAGE_STRERO_RTMP_SERVER),ENABLE_RTMP_SERVER=1,) \
		$(if $(BR2_PACKAGE_STRERO_RTMP_CLIENT),ENABLE_RTMP_CLIENT=1,) \
		$(if $(BR2_PACKAGE_STRERO_TLS_OPENSSL),RTMPS_BACKEND_OPENSSL=1,) \
		$(if $(BR2_PACKAGE_STRERO_TLS_MBEDTLS),RTMPS_BACKEND_MBEDTLS=1,) \
		$(if $(BR2_PACKAGE_STRERO_WEBRTC),WEBRTC_ENABLED=1,) \
		-C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

define STRERO_INSTALL_TARGET_CMDS
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
	$(INSTALL) -D -m 0755 $(STRERO_PKGDIR)/files/S94streamer-watchdog \
		$(TARGET_DIR)/etc/init.d/S94streamer-watchdog

	# Install streamer service
	$(INSTALL) -D -m 0755 $(STRERO_PKGDIR)/files/S95streamer \
		$(TARGET_DIR)/etc/init.d/S95streamer

	# Install watchdog configuration
	$(INSTALL) -D -m 0644 $(STRERO_PKGDIR)/files/streamer-watchdog.conf \
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
	$(INSTALL) -D -m 0755 $(STRERO_PKGDIR)/files/generate-ssl-certs.sh \
		$(TARGET_DIR)/usr/bin/generate-ssl-certs.sh
endef

# Post-install hook to generate SSL certificates for TLS-enabled builds
define STRERO_POST_INSTALL_TARGET_HOOKS_CMD
	# Generate SSL certificates if TLS support is enabled
	if [ "$(BR2_PACKAGE_STRERO_TLS_OPENSSL)" = "y" ]; then \
		echo "Generating SSL certificates for Strero..."; \
		mkdir -p $(TARGET_DIR)/etc/ssl/certs $(TARGET_DIR)/etc/ssl/private; \
		if [ "$(BR2_PACKAGE_STRERO_TLS_OPENSSL)" = "y" ]; then \
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

STRERO_POST_INSTALL_TARGET_HOOKS += STRERO_POST_INSTALL_TARGET_HOOKS_CMD

$(eval $(generic-package))
