################################################################################
#
# timps — Tiny IMP Streamer
#
################################################################################

TIMPS_SITE_METHOD = git
TIMPS_SITE = https://github.com/Lu-Fi/timps
TIMPS_VERSION = v1.3.5

# Submodule provides the IMP headers (ingenic-headers).
TIMPS_GIT_SUBMODULES = YES

TIMPS_DEPENDENCIES = ingenic-lib
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	TIMPS_DEPENDENCIES += ingenic-musl
endif
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	TIMPS_DEPENDENCIES += ingenic-uclibc
endif

ifeq ($(BR2_PACKAGE_TIMPS_FAAC),y)
	TIMPS_DEPENDENCIES += faac
endif

ifeq ($(BR2_PACKAGE_TIMPS_TLS),y)
	TIMPS_DEPENDENCIES += mbedtls
endif

ifeq ($(BR2_PACKAGE_TIMPS_SRT),y)
	TIMPS_DEPENDENCIES += libsrt
endif

# CFLAGS inherit TARGET_CFLAGS for arch-specific flags (critical for XBurst CPUs
# which need -mno-fused-madd / -ffp-contract=off). The timps Makefile adds its
# own -DUSE_* defines based on the USE_* variables we pass below, so we only
# add platform, kernel, and libc flags here.
TIMPS_CFLAGS = $(TARGET_CFLAGS) \
	-std=c11 -D_GNU_SOURCE -Os \
	-Wall -Wextra -Wno-unused-parameter -Wno-misleading-indentation \
	-Wno-stringop-truncation -ffunction-sections -fdata-sections

TIMPS_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION),4.4.94)
	TIMPS_CFLAGS += -DKERNEL_VERSION_4
endif

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	TIMPS_CFLAGS += -DLIBC_GLIBC
endif
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	TIMPS_CFLAGS += -DLIBC_UCLIBC
endif

# Buildroot staging has shared (.so) versions of the IMP libs, not static (.a).
# The upstream Makefile defaults to static: -l:libimp.a etc.
# We override to use the shared libraries installed by ingenic-lib.
TIMPS_IMPLIBS = -limp -lalog -lsysutils

# Additional system libs (extended from upstream -lpthread -lrt -lm)
TIMPS_LIBS = -lpthread -lrt -lm

ifeq ($(BR2_PACKAGE_TIMPS_TLS),y)
	TIMPS_LIBS += -lmbedtls -lmbedx509 -lmbedcrypto
endif

ifeq ($(BR2_PACKAGE_TIMPS_SRT),y)
	TIMPS_LIBS += -lsrt
endif

define TIMPS_BUILD_CMDS
	$(MAKE) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		PLATFORM=$(shell echo $(SOC_FAMILY) | tr a-z A-Z) \
		IMP_LIB=$(STAGING_DIR)/usr/lib \
		IMPLIBS="$(TIMPS_IMPLIBS)" \
		FAACLIB="-lfaac" \
		CFLAGS="$(TIMPS_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -L$(STAGING_DIR)/usr/lib -L$(TARGET_DIR)/usr/lib" \
		LIBS="$(TIMPS_LIBS)" \
		USE_FAAC=$(if $(BR2_PACKAGE_TIMPS_FAAC),1,0) \
		USE_CONTROL=$(if $(BR2_PACKAGE_TIMPS_CONTROL),1,0) \
		USE_DAYNIGHT=$(if $(BR2_PACKAGE_TIMPS_DAYNIGHT),1,0) \
		USE_TLS=$(if $(BR2_PACKAGE_TIMPS_TLS),1,0) \
		USE_SRT=$(if $(BR2_PACKAGE_TIMPS_SRT),1,0) \
		-C $(@D) target
endef

define TIMPS_INSTALL_TARGET_CMDS
	# Install the streamer binary
	$(INSTALL) -D -m 0755 $(@D)/timpsd \
		$(TARGET_DIR)/usr/bin/timpsd

	# Copy to NFS share for dev iteration
	[ -d /nfs ] && cp $(TARGET_DIR)/usr/bin/timpsd /nfs/timpsd || true

	# Install default configuration file
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/timps.conf \
		$(TARGET_DIR)/etc/timps.conf

	# Install init script
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/S95timps \
		$(TARGET_DIR)/etc/init.d/S95timps

	# Install TLS certificate generation script if TLS is enabled
	if [ "$(BR2_PACKAGE_TIMPS_TLS)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/generate-tls-certs.sh \
			$(TARGET_DIR)/usr/bin/generate-timps-tls-certs.sh; \
	fi

	# Install the self-test helper
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/timps-selftest.sh \
		$(TARGET_DIR)/usr/bin/timps-selftest

	# Install the day/night ISP hook (/usr/sbin/color) when native day/night
	# detection is enabled; timps calls it to drive the ircut/light/gain
	# switching through thingino's daynight scripts.
	if [ "$(BR2_PACKAGE_TIMPS_DAYNIGHT)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/color \
			$(TARGET_DIR)/usr/sbin/color; \
	fi
endef

# NOTE: WebUI bridge CGIs. The stock WebUI settings pages POST prudynt-shaped
# JSON to /x/json-prudynt*.cgi, /x/json-imp.cgi and /x/restart-prudynt.cgi.
# files/www/x/ ships timps-flavored replacements (same names) that translate
# the supported subset to timps's /control JSON API on 127.0.0.1:8880, plus the
# native page scripts (files/www/a/) and pages (files/www/*.html). They are
# installed via a TARGET_FINALIZE_HOOK so they override the thingino-webui
# copies regardless of package build order, and only when both the WebUI and the
# timps /control endpoint are enabled. The whole directory is installed (CGIs and
# the .sh lib alike; busybox httpd executes anything under /x/ regardless of
# extension). The WebUI's own prudynt-flavored bridge CGIs (they shell out to the
# absent prudyntctl) are purged so a timps image carries no dead endpoints, and
# the busybox httpd "/mjpeg" convenience alias is repointed at timps's own MJPEG
# endpoint (localhost -> no auth needed; uses the default http.port 8880).
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI)$(BR2_PACKAGE_TIMPS_CONTROL),yy)
define TIMPS_INSTALL_WEBUI_CGIS
	# timps-flavored WebUI: overlay every timps-specific asset over the stock
	# thingino-webui install so the settings pages talk to timps /control +
	# /events directly (a/timps-api.js). Kept ENTIRELY in this package so
	# thingino-webui stays pristine/upstream; the finalize hook wins regardless
	# of package build order. x/ = the surviving structural CGIs (token, restart,
	# GPIO json-imp, heartbeat); a/ = the native page scripts; *.html = the pages.
	for f in $(TIMPS_PKGDIR)/files/www/x/* ; do \
		$(INSTALL) -D -m 0755 $$f $(TARGET_DIR)/var/www/x/$$(basename $$f) ; \
	done
	for f in $(TIMPS_PKGDIR)/files/www/a/* ; do \
		$(INSTALL) -D -m 0644 $$f $(TARGET_DIR)/var/www/a/$$(basename $$f) ; \
	done
	for f in $(TIMPS_PKGDIR)/files/www/*.html ; do \
		$(INSTALL) -D -m 0644 $$f $(TARGET_DIR)/var/www/$$(basename $$f) ; \
	done
	# purge the stock files timps replaces with native /control logic: the dead
	# prudynt bridge CGIs and orphaned scripts, so a timps image carries none.
	rm -f $(TARGET_DIR)/var/www/a/audio.js \
	      $(TARGET_DIR)/var/www/a/streamer-config.js \
	      $(TARGET_DIR)/var/www/x/json-prudynt.cgi \
	      $(TARGET_DIR)/var/www/x/json-imaging.cgi \
	      $(TARGET_DIR)/var/www/x/json-prudynt-config.cgi \
	      $(TARGET_DIR)/var/www/x/json-prudynt-save.cgi \
	      $(TARGET_DIR)/var/www/x/json-timegraph-stream.cgi
	rm -f $(TARGET_DIR)/var/www/x/ch0.mjpg $(TARGET_DIR)/var/www/x/ch1.mjpg \
	      $(TARGET_DIR)/var/www/x/ch0.jpg  $(TARGET_DIR)/var/www/x/ch1.jpg
	if [ -f $(TARGET_DIR)/etc/httpd.conf ]; then \
		sed -i 's#^P:/mjpeg:.*#P:/mjpeg:http://127.0.0.1:8880/stream.mjpeg#' \
			$(TARGET_DIR)/etc/httpd.conf ; \
		sed -i '\#^P:/onvif/image\.cgi:#d' $(TARGET_DIR)/etc/httpd.conf ; \
		echo 'P:/onvif/image.cgi:http://127.0.0.1:8880/snapshot.jpg?chn=0' \
			>> $(TARGET_DIR)/etc/httpd.conf ; \
	fi
	# ch0.jpg above was thingino-onvif's snapshot source (onvif/image.cgi ->
	# x/ch0.jpg); with it gone that symlink is dangling. timps has no static
	# snapshot file, so proxy the ONVIF snapshot URL straight to timps's own
	# endpoint instead (same P: mechanism as /mjpeg above; loopback so no
	# token is needed, see httpd.c's 127.0.0.0/8 auth bypass).
	rm -f $(TARGET_DIR)/var/www/onvif/image.cgi
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_INSTALL_WEBUI_CGIS
endif

# NOTE: send-to-* notification toolkit (email/ftp/ntfy/storage/telegram/
# webhook + the send2common helper they share). The unmodified send2* tools and
# prudynt-helpers are re-installed as-is from package/prudynt-t/files/. The two
# files timps has to ADAPT are shipped as timps's OWN copies under
# package/timps/files/ instead of patching the shared prudynt-t / thingino-webui
# files: send2common (prudyntctl -> timps /snapshot.jpg fallback) and
# telegram-cam-register (snapshot via /onvif/image.cgi instead of /x/ch0.jpg).
# Re-sync those two from upstream when the shared originals change (e.g. the
# send2 shell-injection hardening).
# thingino-webui's telegram-cam-agent (MQTT "snap"/"clip" commands) and the
# stock Send-to config pages are installed on every image regardless of
# streamer (gated only on BR2_THINGINO_DEV_IPCAM), so without this the
# scripts they call are simply missing on a timps image. Install from a
# finalize hook (not a normal package dependency) so this doesn't require
# enabling the prudynt-t Buildroot package itself.
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI)$(BR2_THINGINO_DEV_IPCAM),yy)
PRUDYNT_T_FILES_DIR = $(PRUDYNT_T_PKGDIR)/files
define TIMPS_INSTALL_SEND2
	$(INSTALL) -D -m 0644 $(PRUDYNT_T_FILES_DIR)/prudynt-helpers \
		$(TARGET_DIR)/usr/share/prudynt-helpers
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/send2common \
		$(TARGET_DIR)/usr/share/send2common
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/telegram-cam-register \
		$(TARGET_DIR)/usr/sbin/telegram-cam-register
	for f in send2email send2ftp send2ntfy send2storage send2telegram send2webhook; do \
		$(INSTALL) -D -m 0755 $(PRUDYNT_T_FILES_DIR)/$$f $(TARGET_DIR)/usr/sbin/$$f ; \
	done
	[ -f $(TARGET_DIR)/etc/send2.json ] || \
		$(INSTALL) -D -m 0644 $(PRUDYNT_T_FILES_DIR)/send2.json \
			$(TARGET_DIR)/etc/send2.json
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_INSTALL_SEND2
endif

# NOTE: preview page. thingino-webui picks the preview page (preview.html) at
# ITS install time from the selected streamer, so switching raptor->timps
# without rebuilding thingino-webui leaves raptor's WebRTC preview behind (it
# POSTs to /x/webrtc-whip.cgi -> 502, no image). Install our self-contained
# MSE/fMP4 preview (fetches :8880/stream.mp4) over /var/www/preview.html from a
# finalize hook so it wins regardless of package build order. Only when the
# WebUI is present. preview-timps.html lives in THIS package (files/www/)
# together with the rest of the timps WebUI overlay, so thingino-webui stays
# pristine.
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
TIMPS_PREVIEW_SRC = $(TIMPS_PKGDIR)/files/www/preview-timps.html
define TIMPS_INSTALL_PREVIEW
	$(INSTALL) -D -m 0644 $(TIMPS_PREVIEW_SRC) \
		$(TARGET_DIR)/var/www/preview.html
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_INSTALL_PREVIEW
endif

# NOTE: native day/night. When timps detects day/night itself
# (BR2_PACKAGE_TIMPS_DAYNIGHT), the standalone daynightd daemon must never
# autostart (double switching), and the WebUI "Photosensing" page (which
# configures daynightd) is dropped from the navigation. Done as a finalize
# hook so it wins regardless of package build order; both steps are
# idempotent and no-ops when the files are absent.
ifeq ($(BR2_PACKAGE_TIMPS_DAYNIGHT),y)
define TIMPS_DISABLE_DAYNIGHTD
	rm -f $(TARGET_DIR)/etc/init.d/S97daynightd
	if [ -f $(TARGET_DIR)/var/www/a/navigation.js ]; then \
		sed -i '/config-photosensing\.html/d' \
			$(TARGET_DIR)/var/www/a/navigation.js ; \
	fi
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_DISABLE_DAYNIGHTD
endif

# NOTE: ONVIF discovery script. thingino-onvif deliberately does NOT ship
# S96onvif_discovery ("streamer-specific and installed by the selected streamer
# package"); raptor/prudynt/strero each install their OWN raptor-flavored copy
# that builds /etc/onvif.json from raptorctl. On a timps image that copy is
# wrong (ONVIF credentials come back empty/raptor -> clients fail to log in) and
# Buildroot leaves the stale file behind when switching streamer choice. Install
# timps's own S96onvif_discovery - it sources the ONVIF user/pass and stream URLs
# from /etc/timps.conf instead. Done as a finalize hook (like the WebUI overlay)
# so it wins over any leftover raptor/prudynt copy regardless of build order.
#
# We deliberately do NOT gate on $(BR2_PACKAGE_THINGINO_ONVIF): in practice
# ONVIF can be present in the image while that symbol reads "not set" (pulled in
# indirectly, or left over in target/ from an earlier build), and the finalize
# hook must ALSO overwrite a stale raptor/prudynt S96onvif_discovery that
# Buildroot left behind. So the hook is always registered and decides at
# finalize time by probing the target: install our copy whenever the ONVIF
# daemon is present, or whenever some other streamer already dropped an S96.
# On a genuinely ONVIF-free image neither is true and nothing is shipped.
define TIMPS_INSTALL_ONVIF_DISCOVERY
	if [ -e $(TARGET_DIR)/usr/sbin/wsd_simple_server ] || \
	   [ -e $(TARGET_DIR)/var/www/onvif/onvif.cgi ] || \
	   [ -e $(TARGET_DIR)/etc/init.d/S96onvif_discovery ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/S96onvif_discovery \
			$(TARGET_DIR)/etc/init.d/S96onvif_discovery ; \
	fi
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_INSTALL_ONVIF_DISCOVERY

$(eval $(generic-package))
