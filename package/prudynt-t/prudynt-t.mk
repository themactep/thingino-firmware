PRUDYNT_T_SITE_METHOD = git
# PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_SITE = https://github.com/themactep/prudynt-t
PRUDYNT_T_SITE_BRANCH = stable
PRUDYNT_T_VERSION = 09ca87e2bf68e15aa3c15d7c092a1bcdbead9916

PRUDYNT_T_OVERRIDE_FILE = $(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/prudynt-override.json

PRUDYNT_T_GIT_SUBMODULES = YES

PRUDYNT_T_DEPENDENCIES += ingenic-lib
PRUDYNT_T_DEPENDENCIES += host-thingino-jct thingino-jct
PRUDYNT_T_DEPENDENCIES += thingino-live555
PRUDYNT_T_DEPENDENCIES += thingino-libcurl
PRUDYNT_T_DEPENDENCIES += opus faac libhelix-aac libhelix-mp3 libflac
PRUDYNT_T_DEPENDENCIES += libschrift

ifeq ($(BR2_PACKAGE_PRUDYNT_T_FFMPEG),y)
	PRUDYNT_T_DEPENDENCIES += thingino-ffmpeg
	PRUDYNT_T_CFLAGS += -DUSE_FFMPEG
endif

ifeq ($(BR2_PACKAGE_PRUDYNT_T_WEBRTC),y)
#	PRUDYNT_T_DEPENDENCIES += libpeer
	PRUDYNT_T_DEPENDENCIES += libdatachannel
	# libdatachannel brings its own SSL/TLS dependency (OpenSSL or mbedTLS)
endif

ifeq ($(BR2_PACKAGE_PRUDYNT_T_WEBSOCKETS),y)
	PRUDYNT_T_DEPENDENCIES += libwebsockets
	PRUDYNT_T_DEPENDENCIES += host-thingino-jct
	PRUDYNT_T_CFLAGS += -DUSE_WEBSOCKETS
endif

# Pre-trigger buffer support
ifeq ($(BR2_PACKAGE_PRUDYNT_T_PREBUFFER),y)
	PRUDYNT_T_PREBUFFER_ENABLED = 1
else
	PRUDYNT_T_PREBUFFER_ENABLED = 0
endif

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	PRUDYNT_T_DEPENDENCIES += ingenic-musl libexecinfo
endif

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	PRUDYNT_CFLAGS += -DLIBC_GLIBC
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	PRUDYNT_CFLAGS += -DLIBC_UCLIBC
endif

PRUDYNT_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION_4),y)
	PRUDYNT_CFLAGS += -DKERNEL_VERSION_4
endif

# Base compiler flags
PRUDYNT_CFLAGS += \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/liveMedia \
	-I$(STAGING_DIR)/usr/include/groupsock \
	-I$(STAGING_DIR)/usr/include/UsageEnvironment \
	-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

# OpenSSL support - link against OpenSSL if available and live555 uses it
ifeq ($(BR2_PACKAGE_OPENSSL),y)
PRUDYNT_T_DEPENDENCIES += host-pkgconf openssl
PRUDYNT_LDFLAGS += `$(PKG_CONFIG_HOST_BINARY) --libs openssl`
else
PRUDYNT_CFLAGS += -DNO_OPENSSL=1
endif

# Build mode selection
ifeq ($(BR2_PACKAGE_PRUDYNT_T_STATIC),y)
PRUDYNT_CFLAGS += -DBINARY_STATIC
else ifeq ($(BR2_PACKAGE_PRUDYNT_T_HYBRID),y)
PRUDYNT_CFLAGS += -DBINARY_HYBRID
else
PRUDYNT_CFLAGS += -DBINARY_DYNAMIC
endif

# Debug vs Production build flags
ifeq ($(BR2_PACKAGE_PRUDYNT_T_DEBUG),y)
	# Debug build: disable optimizations, add debug symbols
	PRUDYNT_CFLAGS += -O0 -g -fno-omit-frame-pointer
	PRUDYNT_CFLAGS += -Wnull-dereference -Wformat=2 -Wformat-security -Wstack-protector
	PRUDYNT_CFLAGS += -fstack-protector-strong -D_FORTIFY_SOURCE=2
	PRUDYNT_CFLAGS += -DDEBUG_BUILD=1 -DMEMORY_SAFETY_CHECKS=1

	# Sanitizer support - simplified approach to avoid makefile complexity
	# Try AddressSanitizer first (better cross-compilation support)
ifneq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	# For glibc/uclibc toolchains, try both sanitizers
	PRUDYNT_CFLAGS += -fsanitize=address
	PRUDYNT_LDFLAGS += -fsanitize=address
$(info [PRUDYNT DEBUG] AddressSanitizer enabled for non-musl toolchain)
else
	# For musl toolchains, use alternative memory safety features
	PRUDYNT_CFLAGS += -fstack-clash-protection
$(info [PRUDYNT DEBUG] Alternative memory safety flags enabled for musl toolchain)
endif

	# Prevent buildroot from stripping debug builds
	# Use buildroot's built-in mechanism to preserve debug symbols
	PRUDYNT_T_STRIP_BINARY = NO
else
	# Production build: optimize for size
	PRUDYNT_CFLAGS += -Os
	PRUDYNT_T_STRIP_BINARY = YES
endif

ifeq ($(BR2_PACKAGE_PRUDYNT_T_WEBRTC),y)
PRUDYNT_CFLAGS += \
	-DWEBRTC_ENABLED=1 \
	-DLIBDATACHANNEL_ENABLED=1 \
	-DLIBPEER_AVAILABLE=1 \
	-I$(STAGING_DIR)/usr/include

# Link against SSL library based on what's available (OpenSSL preferred)
ifeq ($(BR2_PACKAGE_OPENSSL),y)
PRUDYNT_LDFLAGS += -ldatachannel -lusrsctp -lssl -lcrypto -ljuice
else
PRUDYNT_LDFLAGS += -ldatachannel -lusrsctp -lmbedtls -lmbedx509 -lmbedcrypto -ljuice
endif
endif

PRUDYNT_LDFLAGS += $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	PRUDYNT_LDFLAGS += -lexecinfo
endif

define PRUDYNT_T_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="$(PRUDYNT_CFLAGS)" \
		LDFLAGS="$(PRUDYNT_LDFLAGS)" \
		SDK_VERSION="$(SDK_VERSION)" \
		$(if $(filter y,$(BR2_PACKAGE_PRUDYNT_T_DEBUG)),DEBUG=1 DEBUG_STRIP=0,DEBUG_STRIP=1) \
		$(if $(BR2_PACKAGE_PRUDYNT_T_FFMPEG),USE_FFMPEG=1) \
		$(if $(BR2_PACKAGE_PRUDYNT_T_WEBRTC),WEBRTC_ENABLED=1,) \
		$(if $(BR2_PACKAGE_PRUDYNT_T_WEBSOCKETS),USE_WEBSOCKETS=1,USE_WEBSOCKETS=0) \
		USE_PREBUFFER=$(PRUDYNT_T_PREBUFFER_ENABLED) \
		-C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

define PRUDYNT_T_INSTALL_TARGET_CMDS
	# Always install stripped binary for firmware (keeps image size small)
	$(TARGET_CROSS)strip $(@D)/bin/prudynt -o $(TARGET_DIR)/usr/bin/prudynt
	chmod 755 $(TARGET_DIR)/usr/bin/prudynt
	echo "Installed stripped prudynt binary ($$(du -h $(TARGET_DIR)/usr/bin/prudynt | cut -f1))"

	[ -d /nfs ] && cp $(TARGET_DIR)/usr/bin/prudynt /nfs/prudynt || true

	# Copy prudyntctl
	cp $(@D)/bin/prudyntctl $(TARGET_DIR)/usr/bin/prudyntctl

	if [ "$(BR2_PACKAGE_PRUDYNT_T_FFMPEG)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/ffmpeg-rtsp \
			$(TARGET_DIR)/usr/sbin/ffmpeg-rtsp; \
		$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/thingino-stream \
			$(TARGET_DIR)/usr/sbin/thingino-stream; \
	fi

	# For debug builds, mandate NFS and install all debug components there
	if [ "$(BR2_PACKAGE_PRUDYNT_T_DEBUG)" = "y" ]; then \
		echo "Debug build detected - installing debug components to NFS..."; \
		if [ -z $(BR2_THINGINO_NFS) ]; then \
			echo "ERROR: Debug build requires BR2_THINGINO_NFS configuration"; \
			echo "Please set BR2_THINGINO_NFS to your NFS mount point and rebuild"; \
			exit 1; \
		fi; \
		if [ ! -d $(BR2_THINGINO_NFS) ]; then \
			echo "ERROR: BR2_THINGINO_NFS directory does not exist: $(BR2_THINGINO_NFS)"; \
			echo "Please create the NFS directory and rebuild"; \
			exit 1; \
		fi; \
		echo "Installing debug components to NFS: $(BR2_THINGINO_NFS)/$(CAMERA)"; \
		mkdir -p $(BR2_THINGINO_NFS)/$(CAMERA)/usr/bin; \
		mkdir -p $(BR2_THINGINO_NFS)/$(CAMERA)/usr/lib/debug/usr/bin; \
		mkdir -p $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share; \
		$(INSTALL) -D -m 0755 $(@D)/bin/prudynt \
			$(BR2_THINGINO_NFS)/$(CAMERA)/usr/bin/prudynt-debug; \
		$(TARGET_CROSS)objcopy --only-keep-debug $(@D)/bin/prudynt \
			$(BR2_THINGINO_NFS)/$(CAMERA)/usr/lib/debug/usr/bin/prudynt.debug; \
		echo "Unstripped debug binary: $(BR2_THINGINO_NFS)/$(CAMERA)/usr/bin/prudynt-debug ($$(du -h $(@D)/bin/prudynt | cut -f1))"; \
		echo "Debug symbols: $(BR2_THINGINO_NFS)/$(CAMERA)/usr/lib/debug/usr/bin/prudynt.debug"; \
		echo "#!/bin/sh" > $(TARGET_DIR)/usr/bin/prudynt-debug-info; \
		echo "echo 'Debug components installed to NFS: $(BR2_THINGINO_NFS)/$(CAMERA)'" >> $(TARGET_DIR)/usr/bin/prudynt-debug-info; \
		echo "echo 'Unstripped binary: /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug'" >> $(TARGET_DIR)/usr/bin/prudynt-debug-info; \
		echo "echo 'Debug symbols: /mnt/nfs/$(CAMERA)/usr/lib/debug/usr/bin/prudynt.debug'" >> $(TARGET_DIR)/usr/bin/prudynt-debug-info; \
		echo "echo 'Debug tools: /mnt/nfs/$(CAMERA)/usr/bin/prudynt-*'" >> $(TARGET_DIR)/usr/bin/prudynt-debug-info; \
		chmod 755 $(TARGET_DIR)/usr/bin/prudynt-debug-info; \
	fi

	# Copy the JSON configuration file to staging
	cp $(PRUDYNT_T_PKGDIR)/files/prudynt.json $(STAGING_DIR)/prudynt.json

	# Apply optional camera override using host jct
	if [ -f "$(PRUDYNT_T_OVERRIDE_FILE)" ]; then \
		if [ ! -x "$(HOST_DIR)/bin/jct" ]; then \
			echo "ERROR: host jct tool missing: $(HOST_DIR)/bin/jct"; \
			exit 1; \
		fi; \
		echo "Applying Prudynt override from $(PRUDYNT_T_OVERRIDE_FILE)"; \
		$(HOST_DIR)/bin/jct $(STAGING_DIR)/prudynt.json import "$(PRUDYNT_T_OVERRIDE_FILE)"; \
	fi

	# Merge websockets configuration if enabled
	if [ "$(BR2_PACKAGE_PRUDYNT_T_WEBSOCKETS)" = "y" ]; then \
		if [ ! -x "$(HOST_DIR)/bin/jct" ]; then \
			echo "ERROR: host jct tool missing: $(HOST_DIR)/bin/jct"; \
			exit 1; \
		fi; \
		echo "Merging websockets configuration"; \
		$(HOST_DIR)/bin/jct $(STAGING_DIR)/prudynt.json import "$(PRUDYNT_T_PKGDIR)/files/websockets.json"; \
	fi

	# Install the final, modified JSON file from staging to target
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/prudynt.json \
		$(TARGET_DIR)/etc/prudynt.json

	# scripts (video)
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/imp-control \
		$(TARGET_DIR)/usr/sbin/imp-control
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/color \
		$(TARGET_DIR)/usr/sbin/color
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/motion \
		$(TARGET_DIR)/usr/sbin/motion
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/privacy \
		$(TARGET_DIR)/usr/sbin/privacy
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/timelapse \
		$(TARGET_DIR)/usr/sbin/timelapse
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/daynight \
		$(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/metrics \
		$(TARGET_DIR)/var/www/x/metrics

	# send2 scripts
	$(INSTALL) -D -m 0644 $(PRUDYNT_T_PKGDIR)/files/send2.json \
		$(TARGET_DIR)/etc/send2.json
	$(INSTALL) -D -m 0644 $(PRUDYNT_T_PKGDIR)/files/send2common \
		$(TARGET_DIR)/usr/share/send2common
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2email \
		$(TARGET_DIR)/usr/sbin/send2email
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2ftp \
		$(TARGET_DIR)/usr/sbin/send2ftp
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2gphotos \
		$(TARGET_DIR)/usr/sbin/send2gphotos
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2mqtt \
		$(TARGET_DIR)/usr/sbin/send2mqtt
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2ntfy \
		$(TARGET_DIR)/usr/sbin/send2ntfy
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2storage \
		$(TARGET_DIR)/usr/sbin/send2storage
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2telegram \
		$(TARGET_DIR)/usr/sbin/send2telegram
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/send2webhook \
		$(TARGET_DIR)/usr/sbin/send2webhook

	# scripts (audio)
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/microphone \
		$(TARGET_DIR)/usr/sbin/microphone
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/speaker \
		$(TARGET_DIR)/usr/sbin/speaker
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/play \
		$(TARGET_DIR)/usr/sbin/play
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/record \
		$(TARGET_DIR)/usr/sbin/record
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/tell \
		$(TARGET_DIR)/usr/sbin/tell

	# services
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/S31prudynt \
		$(TARGET_DIR)/etc/init.d/S31prudynt
#	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/S32prudyntwd \
#		$(TARGET_DIR)/etc/init.d/S32prudyntwd
	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/S98recorder \
		$(TARGET_DIR)/etc/init.d/S98recorder

	# assets
	$(INSTALL) -D -m 0644 $(@D)/res/default.ttf \
		$(TARGET_DIR)/usr/share/fonts/default.ttf
	$(INSTALL) -D -m 0644 $(@D)/res/thingino_100x30.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_100x30.bgra
	$(INSTALL) -D -m 0644 $(@D)/res/thingino_210x64.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_210x64.bgra

	# Install debug-specific files and configurations to NFS
	if [ "$(BR2_PACKAGE_PRUDYNT_T_DEBUG)" = "y" ]; then \
		echo "Installing debug tools and documentation to NFS..."; \
		$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/scripts/prudynt-debug-helper.sh \
			$(BR2_THINGINO_NFS)/$(CAMERA)/usr/bin/prudynt-debug-helper; \
		if [ -f $(@D)/test_memory_safety.sh ]; then \
			$(INSTALL) -D -m 0755 $(@D)/test_memory_safety.sh \
				$(BR2_THINGINO_NFS)/$(CAMERA)/usr/bin/prudynt-test-memory; \
		fi; \
		echo "Prudynt Debug Build Information for $(CAMERA)" > $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "Built with debug symbols and memory safety features" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "Debug symbols: /mnt/nfs/$(CAMERA)/usr/lib/debug/usr/bin/prudynt.debug" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "Unstripped binary: /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "Memory safety features: stack protection, fortify source, debug flags" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		if [ "$(BR2_TOOLCHAIN_USES_MUSL)" = "y" ]; then \
			echo "Toolchain: musl (AddressSanitizer disabled, alternative protections enabled)" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		else \
			echo "Toolchain: glibc/uclibc (AddressSanitizer enabled)" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		fi; \
		echo "" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "Usage (from camera with NFS mounted):" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug-helper check   - Check available debug features" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug-helper run     - Run with debug options" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug-helper gdb     - Debug with GDB" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug                - Run unstripped binary directly" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  /mnt/nfs/$(CAMERA)/usr/bin/prudynt-test-memory          - Run memory safety tests" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "GDB Usage:" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  gdb /mnt/nfs/$(CAMERA)/usr/bin/prudynt-debug" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "  gdb /usr/bin/prudynt -s /mnt/nfs/$(CAMERA)/usr/lib/debug/usr/bin/prudynt.debug" >> $(BR2_THINGINO_NFS)/$(CAMERA)/usr/share/prudynt-debug-info.txt; \
		echo "Debug tools installed to NFS: prudynt-debug-helper, prudynt-test-memory"; \
	fi
endef

$(eval $(generic-package))
