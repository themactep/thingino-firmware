THINGINO_RAPTOR_VERSION = 17804903e1414d426802df0967b3bdbd72219f58
THINGINO_RAPTOR_SITE = https://github.com/gtxaspec/raptor
THINGINO_RAPTOR_SITE_METHOD = git

THINGINO_RAPTOR_LICENSE = GPL-3.0
THINGINO_RAPTOR_LICENSE_FILES = COPYING

THINGINO_RAPTOR_DEPENDENCIES += ingenic-lib compy libschrift
THINGINO_RAPTOR_DEPENDENCIES += thingino-raptor-hal thingino-raptor-ipc thingino-raptor-common
THINGINO_RAPTOR_DEPENDENCIES += thingino-webui thingino-agent
ifeq ($(BR2_PACKAGE_OPENIMP),y)
THINGINO_RAPTOR_DEPENDENCIES += openimp
THINGINO_RAPTOR_MAKE_OPTS += V4L2_OPENIMP=1
endif
ifeq ($(BR2_PACKAGE_INGENIC_SYSTEM_LIBS_NEO),y)
THINGINO_RAPTOR_DEPENDENCIES += ingenic-system-libs-neo
endif
ifeq ($(BR2_PACKAGE_LIBAUDIOPROCESS_NEO),y)
THINGINO_RAPTOR_DEPENDENCIES += libaudioprocess-neo
endif

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

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_IVS_DETECT),y)
THINGINO_RAPTOR_MAKE_OPTS += IVS_DETECT=1
ifeq ($(BR2_PACKAGE_INGENIC_LIB_PERSONDET),y)
THINGINO_RAPTOR_MAKE_OPTS += PERSONDET=1
endif
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_DEBUG),y)
THINGINO_RAPTOR_MAKE_OPTS += DEBUG=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_WEBTORRENT),y)
THINGINO_RAPTOR_MAKE_OPTS += WEBTORRENT=1
endif

# Per-daemon build targets (tools always built)
THINGINO_RAPTOR_TARGETS = raptorctl ringdump

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RVD),y)
THINGINO_RAPTOR_TARGETS += rvd
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RAC),y)
THINGINO_RAPTOR_TARGETS += rac
endif

ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RSD),y)
THINGINO_RAPTOR_TARGETS += rsd
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RSD555),y)
THINGINO_RAPTOR_TARGETS += rsd-555
THINGINO_RAPTOR_DEPENDENCIES += live555
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
THINGINO_RAPTOR_TARGETS += rmr rverify
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
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RSP),y)
THINGINO_RAPTOR_TARGETS += rsp
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RSR),y)
THINGINO_RAPTOR_TARGETS += rsr
THINGINO_RAPTOR_DEPENDENCIES += libsrt
ifeq ($(BR2_PACKAGE_LIBSRT_STATIC_STDCXX),y)
THINGINO_RAPTOR_MAKE_OPTS += STATIC_STDCXX=1
endif
endif
ifeq ($(BR2_PACKAGE_THINGINO_RAPTOR_RFS),y)
THINGINO_RAPTOR_TARGETS += rfs
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
		LIB_HAL_VIDEO=$(STAGING_DIR)/usr/lib/libraptor_hal_video.a \
		LIB_HAL_VIDEO_FILE=$(STAGING_DIR)/usr/lib/libraptor_hal_video.a \
		LIB_HAL_AUDIO=$(STAGING_DIR)/usr/lib/libraptor_hal_audio.a \
		LIB_HAL_AUDIO_FILE=$(STAGING_DIR)/usr/lib/libraptor_hal_audio.a \
		LIB_IPC="-L$(STAGING_DIR)/usr/lib -lrss_ipc" \
		LIB_IPC_FILE=$(STAGING_DIR)/usr/lib/librss_ipc.so \
		LIB_COMMON="-L$(STAGING_DIR)/usr/lib -lrss_common" \
		LIB_COMMON_FILE=$(STAGING_DIR)/usr/lib/librss_common.so \
		LIB_COMPY=$(STAGING_DIR)/usr/lib/libcompy.a \
		LIB_COMPY_FILE=$(STAGING_DIR)/usr/lib/libcompy.a \
		COMPY_CFLAGS="-I$(STAGING_DIR)/usr/include $(if $(filter TLS=1,$(THINGINO_RAPTOR_MAKE_OPTS)),-DCOMPY_HAS_TLS)" \
		EXTRA_CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
		LIVE555_SYSROOT=$(STAGING_DIR) \
		$(THINGINO_RAPTOR_MAKE_OPTS) \
		-C $(@D) $(THINGINO_RAPTOR_TARGETS)
endef

define THINGINO_RAPTOR_INSTALL_TARGET_CMDS
	# Install the thingino-agent backend adapter at the fixed path, overwriting
	# the null fallback installed by thingino-agent.
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/agent-adapter \
		$(TARGET_DIR)/usr/libexec/agent/adapter.sh

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
	# Install same-origin WHIP proxy used by native preview (no iframe).
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/webrtc-whip.cgi \
		$(TARGET_DIR)/var/www/x/webrtc-whip.cgi

	# WebUI plugin (streamer pages, audio, save/restart CGIs)
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/raptor.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/raptor.webui.json
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/config-audio.html \
		$(TARGET_DIR)/var/www/config-audio.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/streamer-image.html \
		$(TARGET_DIR)/var/www/streamer-image.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/streamer-main.html \
		$(TARGET_DIR)/var/www/streamer-main.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/streamer-osd.html \
		$(TARGET_DIR)/var/www/streamer-osd.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/streamer-sensor.html \
		$(TARGET_DIR)/var/www/streamer-sensor.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/streamer-substream.html \
		$(TARGET_DIR)/var/www/streamer-substream.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/tool-timelapse.html \
		$(TARGET_DIR)/var/www/tool-timelapse.html
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/a/streamer.js \
		$(TARGET_DIR)/var/www/a/streamer.js
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/a/preview-endpoints.js \
		$(TARGET_DIR)/var/www/a/preview-endpoints.js
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/a/streamer-config.js \
		$(TARGET_DIR)/var/www/a/streamer-config.js
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/a/streamer-osd.js \
		$(TARGET_DIR)/var/www/a/streamer-osd.js
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/a/audio.js \
		$(TARGET_DIR)/var/www/a/audio.js
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/a/tool-timelapse.js \
		$(TARGET_DIR)/var/www/a/tool-timelapse.js
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/json-config-save.cgi \
		$(TARGET_DIR)/var/www/x/json-config-save.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/restart-streamer.cgi \
		$(TARGET_DIR)/var/www/x/restart-streamer.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/json-sensor-upload.cgi \
		$(TARGET_DIR)/var/www/x/json-sensor-upload.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/json-timelapse.cgi \
		$(TARGET_DIR)/var/www/x/json-timelapse.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/dl0.jpg \
		$(TARGET_DIR)/var/www/x/dl0.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/dl1.jpg \
		$(TARGET_DIR)/var/www/x/dl1.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/ch0.mjpg \
		$(TARGET_DIR)/var/www/x/ch0.mjpg
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/www/x/ch1.mjpg \
		$(TARGET_DIR)/var/www/x/ch1.mjpg
	# Alias snapshot endpoints used by some send/download helpers
	ln -sf dl0.jpg $(TARGET_DIR)/var/www/x/ch0.jpg
	ln -sf dl1.jpg $(TARGET_DIR)/var/www/x/ch1.jpg

	# Init script — webcam variant includes USB gadget setup
	if [ "$(BR2_THINGINO_DEV_WEBCAM)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(@D)/config/S31raptor-webcam \
			$(TARGET_DIR)/etc/init.d/S31raptor; \
	else \
		$(INSTALL) -D -m 0755 $(@D)/config/S31raptor \
			$(TARGET_DIR)/etc/init.d/S31raptor; \
	fi
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/privacy \
		$(TARGET_DIR)/usr/sbin/privacy
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/microphone \
		$(TARGET_DIR)/usr/sbin/microphone
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/speaker \
		$(TARGET_DIR)/usr/sbin/speaker
	$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/color \
		$(TARGET_DIR)/usr/sbin/color
	# Day/night wrappers belong to RIC; with daynightd selected its
	# own scripts of the same names are the day/night interface.
	if [ "$(BR2_PACKAGE_THINGINO_RAPTOR_RIC)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/daynight \
			$(TARGET_DIR)/usr/sbin/daynight; \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/ircut \
			$(TARGET_DIR)/usr/sbin/ircut; \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/light \
			$(TARGET_DIR)/usr/sbin/light; \
	fi
	if [ "$(BR2_PACKAGE_THINGINO_RAPTOR_RAC)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/record \
			$(TARGET_DIR)/usr/sbin/record; \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/play \
			$(TARGET_DIR)/usr/sbin/play; \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/tell \
			$(TARGET_DIR)/usr/sbin/tell; \
	fi
	if [ "$(BR2_PACKAGE_THINGINO_ONVIF)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/S96onvif_discovery \
			$(TARGET_DIR)/etc/init.d/S96onvif_discovery; \
	fi

	# Motion -> send2 bridge. RMD has no on_motion script hook, so a
	# small watcher polls rmd status and invokes raptor-motion on edges.
	if [ "$(BR2_PACKAGE_THINGINO_RAPTOR_RMD)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/raptor-motion \
			$(TARGET_DIR)/usr/sbin/raptor-motion; \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/raptor-motion-watch \
			$(TARGET_DIR)/usr/sbin/raptor-motion-watch; \
		$(INSTALL) -D -m 0755 $(THINGINO_RAPTOR_PKGDIR)/files/S32raptor-motion \
			$(TARGET_DIR)/etc/init.d/S32raptor-motion; \
		ln -sf raptor-motion $(TARGET_DIR)/usr/sbin/motion; \
	fi

	# Patch raptor.conf with buildroot config overrides
	$(call THINGINO_RAPTOR_PATCH_CONF)

endef

# Raptor's own WebRTC preview page. It must land over thingino-webui's stock
# MJPEG preview.html, and it must be in place BEFORE thingino-webui's
# plugin-assembly finalize hook processes it (the assembler injects plugins.js
# into whatever is on disk at that path). A plain INSTALL_TARGET_CMDS copy goes
# into the per-package tree and loses the final per-package merge to
# thingino-webui (alphabetically later package wins conflicts), so install it
# from a finalize hook: parse order puts this hook before the webui's assembly
# hook, and target-finalize runs after the per-package merge.
define THINGINO_RAPTOR_INSTALL_PREVIEW
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/www/preview.html \
		$(TARGET_DIR)/var/www/preview.html
endef
THINGINO_RAPTOR_TARGET_FINALIZE_HOOKS += THINGINO_RAPTOR_INSTALL_PREVIEW

# Raptor-only send2 capture (copy_photo/copy_video via raptorctl/RMR). Installed
# from a finalize hook so it wins over package/thingino-send2's prudynt default
# regardless of package install order. On a raptor image this is the only
# capture path — no runtime streamer branching.
define THINGINO_RAPTOR_INSTALL_SEND2COMMON
	$(INSTALL) -D -m 0644 $(THINGINO_RAPTOR_PKGDIR)/files/send2common \
		$(TARGET_DIR)/usr/share/send2common
endef
THINGINO_RAPTOR_TARGET_FINALIZE_HOOKS += THINGINO_RAPTOR_INSTALL_SEND2COMMON

include $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-raptor/thingino-raptor-conf.mk

$(eval $(generic-package))
