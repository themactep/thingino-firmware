PRUDYNT_T_SITE_METHOD = git
PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_SITE_BRANCH = master
#PRUDYNT_T_VERSION = 6eab9c0ef6fac8eb80f10ce489bca18295d84729
PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) $(PRUDYNT_T_SITE_BRANCH) | head -1 | cut -f1)

PRUDYNT_T_GIT_SUBMODULES = YES

PRUDYNT_T_DEPENDENCIES = json-c thingino-live555 ingenic-lib libschrift
PRUDYNT_T_DEPENDENCIES += thingino-opus
PRUDYNT_T_DEPENDENCIES += faac libhelix-aac
PRUDYNT_T_DEPENDENCIES += host-jq
PRUDYNT_T_DEPENDENCIES += libwebsockets

ifeq ($(BR2_PACKAGE_PRUDYNT_T_WEBRTC),y)
	PRUDYNT_T_DEPENDENCIES += libpeer
endif

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	PRUDYNT_T_DEPENDENCIES += ingenic-musl
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

PRUDYNT_CFLAGS += \
	-DNO_OPENSSL=1 -Os \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/liveMedia \
	-I$(STAGING_DIR)/usr/include/groupsock \
	-I$(STAGING_DIR)/usr/include/UsageEnvironment \
	-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

ifeq ($(BR2_PACKAGE_PRUDYNT_T_WEBRTC),y)
PRUDYNT_CFLAGS += \
	-DWEBRTC_ENABLED=1 \
	-DLIBPEER_AVAILABLE=1 \
	-I$(STAGING_DIR)/usr/include
endif

PRUDYNT_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

define PRUDYNT_T_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="$(PRUDYNT_CFLAGS)" \
		LDFLAGS="$(PRUDYNT_LDFLAGS)" \
		$(if $(BR2_PACKAGE_PRUDYNT_T_WEBRTC),WEBRTC_ENABLED=1,) \
		-C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

define PRUDYNT_T_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/prudynt \
		$(TARGET_DIR)/usr/bin/prudynt

	# Copy the JSON configuration file
	cp $(@D)/res/prudynt.json $(STAGING_DIR)/prudynt.json

	$(INSTALL) -D -m 0644 $(STAGING_DIR)/prudynt.json \
		$(TARGET_DIR)/etc/prudynt.json

	# Adjust buffer settings for low-memory devices
	if [ "$(SOC_RAM)" -le "64" ]; then \
		$(HOST_DIR)/bin/jq '.stream0.buffers = 1 | .stream1.buffers = 1' \
			$(TARGET_DIR)/etc/prudynt.json > $(TARGET_DIR)/etc/prudynt.json.tmp && \
		mv $(TARGET_DIR)/etc/prudynt.json.tmp $(TARGET_DIR)/etc/prudynt.json; \
	fi

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/S95prudynt \
		$(TARGET_DIR)/etc/init.d/S95prudynt

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/S96record \
		$(TARGET_DIR)/etc/init.d/S96record

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_PKGDIR)/files/S96vbuffer \
		$(TARGET_DIR)/etc/init.d/S96vbuffer

	$(INSTALL) -D -m 0644 $(@D)/res/default.ttf \
		$(TARGET_DIR)/usr/share/fonts/default.ttf

	$(INSTALL) -D -m 0644 $(@D)/res/thingino_100x30.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_100x30.bgra

	$(INSTALL) -D -m 0644 $(@D)/res/thingino_210x64.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_210x64.bgra
endef

$(eval $(generic-package))
