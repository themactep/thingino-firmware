THINGINO_RAPTOR_VERSION = 479cc28
THINGINO_RAPTOR_SITE = https://github.com/gtxaspec/raptor
THINGINO_RAPTOR_SITE_METHOD = git

THINGINO_RAPTOR_LICENSE = GPL-3.0
THINGINO_RAPTOR_LICENSE_FILES = COPYING

THINGINO_RAPTOR_DEPENDENCIES += ingenic-lib compy libschrift
THINGINO_RAPTOR_DEPENDENCIES += thingino-raptor-hal thingino-raptor-ipc thingino-raptor-common

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
THINGINO_RAPTOR_DEPENDENCIES += ingenic-musl
endif

# uclibc shim needed on xburst1 platforms; xburst2 (T40/T41) libs are native uclibc
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
ifeq ($(filter t40 t41,$(SOC_FAMILY)),)
THINGINO_RAPTOR_DEPENDENCIES += ingenic-uclibc
endif
endif

# Platform: uppercase SOC_FAMILY (t31 -> T31)
THINGINO_RAPTOR_PLATFORM = $(shell echo $(SOC_FAMILY) | tr a-z A-Z)

# Feature flags
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_AAC),y)
THINGINO_RAPTOR_MAKE_OPTS += AAC=1
THINGINO_RAPTOR_DEPENDENCIES += faac libhelix-aac
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_OPUS),y)
THINGINO_RAPTOR_MAKE_OPTS += OPUS=1
THINGINO_RAPTOR_DEPENDENCIES += opus
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_MP3),y)
THINGINO_RAPTOR_MAKE_OPTS += MP3=1
THINGINO_RAPTOR_DEPENDENCIES += libhelix-mp3
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_TLS),y)
THINGINO_RAPTOR_MAKE_OPTS += TLS=1
THINGINO_RAPTOR_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_AUDIO_EFFECTS),y)
THINGINO_RAPTOR_MAKE_OPTS += AUDIO_EFFECTS=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_DEBUG),y)
THINGINO_RAPTOR_MAKE_OPTS += DEBUG=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_WEBTORRENT),y)
THINGINO_RAPTOR_MAKE_OPTS += WEBTORRENT=1
endif

# Per-daemon build targets (RVD + tools always built)
THINGINO_RAPTOR_TARGETS = rvd raptorctl ringdump

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RAC),y)
THINGINO_RAPTOR_TARGETS += rac
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RSD),y)
THINGINO_RAPTOR_TARGETS += rsd
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RAD),y)
THINGINO_RAPTOR_TARGETS += rad
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RHD),y)
THINGINO_RAPTOR_TARGETS += rhd
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_ROD),y)
THINGINO_RAPTOR_TARGETS += rod
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RIC),y)
THINGINO_RAPTOR_TARGETS += ric
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RMR),y)
THINGINO_RAPTOR_TARGETS += rmr
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RMD),y)
THINGINO_RAPTOR_TARGETS += rmd
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_WEBRTC),y)
THINGINO_RAPTOR_TARGETS += rwd
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RWC),y)
THINGINO_RAPTOR_TARGETS += rwc
endif

# Libraries are pre-built by their own packages and installed to staging.
# Override LIB_HAL etc. to point at staging .a files.
# Use EXTRA_CFLAGS (not CFLAGS) so the raptor Makefile keeps its own flags.
define THINGINO_RAPTOR_BUILD_CMDS
	$(MAKE) \
		RSS_BUILD_HASH="$(THINGINO_RAPTOR_VERSION)" \
		PLATFORM=$(THINGINO_RAPTOR_PLATFORM) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		SYSROOT=$(STAGING_DIR) \
		LIB_HAL=$(STAGING_DIR)/usr/lib/libraptor_hal.a \
		LIB_IPC=$(STAGING_DIR)/usr/lib/librss_ipc.a \
		LIB_COMMON=$(STAGING_DIR)/usr/lib/librss_common.a \
		LIB_COMPY=$(STAGING_DIR)/usr/lib/libcompy.a \
		COMPY_CFLAGS="-I$(STAGING_DIR)/usr/include $(if $(filter TLS=1,$(THINGINO_RAPTOR_MAKE_OPTS)),-DCOMPY_HAS_TLS)" \
		EXTRA_CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
		$(THINGINO_RAPTOR_MAKE_OPTS) \
		-C $(@D) $(THINGINO_RAPTOR_TARGETS)
endef

define THINGINO_RAPTOR_INSTALL_TARGET_CMDS
	# Install selected daemons and tools
	$(foreach t,$(THINGINO_RAPTOR_TARGETS),\
		if [ -f $(@D)/$(t)/$(t) ]; then \
			$(INSTALL) -D -m 0755 $(@D)/$(t)/$(t) \
				$(TARGET_DIR)/usr/bin/$(t); \
		fi$(sep))

	# Config — use the canonical config from the raptor repo
	$(INSTALL) -D -m 0644 $(@D)/config/raptor.conf \
		$(TARGET_DIR)/etc/raptor.conf

	# Web pages (editable on device)
	$(INSTALL) -D -m 0644 $(@D)/rhd/index.html \
		$(TARGET_DIR)/usr/share/raptor/index.html
	$(INSTALL) -D -m 0644 $(@D)/rwd/webrtc.html \
		$(TARGET_DIR)/usr/share/raptor/webrtc.html

	# Init script
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/S31raptor \
		$(TARGET_DIR)/etc/init.d/S31raptor

	# Patch raptor.conf with buildroot config overrides
	$(call THINGINO_RAPTOR_PATCH_CONF)

endef

include $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-raptor/thingino-raptor-conf.mk

$(eval $(generic-package))
