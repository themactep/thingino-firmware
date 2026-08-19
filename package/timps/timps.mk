################################################################################
#
# timps — Tiny IMP Streamer
#
################################################################################

TIMPS_SITE_METHOD = git
TIMPS_SITE = https://github.com/Lu-Fi/timps
TIMPS_VERSION = v1.9.0
TIMPS_LICENSE = MIT
# Upstream ships no LICENSE file yet; add one and set TIMPS_LICENSE_FILES = LICENSE
# once it exists so legal-info can capture it.

# Build-time VERSION (2026-08 stale-build incident): fw_ota.sh reported
# "flashed successfully" on cameras whose /usr/bin/timpsd binary had
# demonstrably NOT changed post-reboot - a stale cached image kept getting
# reused undetected for hours. GET /control's "version" key (src/control.c's
# MS_VERSION, -DMS_VERSION on the compile command line) exists precisely to
# catch that class of drift from the outside. src/Makefile's own default
# already derives it correctly (`VERSION ?= $(shell git describe --tags
# --always --dirty ... || echo 0.1.0)`), but TIMPS_BUILD_CMDS below passes
# VERSION= explicitly, which overrides that `?=` default - so a real,
# per-commit value has to be computed HERE, not left to src/Makefile.
#
# Local dev loop (local.mk: TIMPS_OVERRIDE_SRCDIR = /path/to/timps checkout):
# Buildroot rsyncs the override dir into $(TIMPS_DIR) using the SAME
# RSYNC_VCS_EXCLUSIONS every package fetch uses (--exclude .git, see
# buildroot/Makefile) - so $(TIMPS_DIR)/.git never exists and a `git
# describe` run from there always fails silently. Verified empirically
# against a real override-srcdir build: $(TIMPS_DIR) (build/timps-custom/)
# carries .gitmodules but no .git. The real .git only exists in
# $(TIMPS_OVERRIDE_SRCDIR) itself, before that rsync - so derive the version
# there instead, at Makefile-parse time (a plain filesystem git-describe on a
# path, no fetch involved, so this is cheap and side-effect-free even when
# unused).
#
# Tag-pinned release path (TIMPS_SITE_METHOD = git fetching TIMPS_VERSION,
# TIMPS_OVERRIDE_SRCDIR unset): there is no local checkout to describe, and
# there shouldn't be - the pinned tag IS already a real, stable, meaningful
# version. Leave it untouched, and also fall back to it whenever the
# override dir's git-describe genuinely isn't available (not a git checkout,
# git missing, etc.) - matching src/Makefile's own "|| echo 0.1.0" fallback
# philosophy: use the real git state when derivable, fall back to the static
# version otherwise.
ifneq ($(call qstrip,$(TIMPS_OVERRIDE_SRCDIR)),)
TIMPS_GIT_DESCRIBE := $(shell git -C $(call qstrip,$(TIMPS_OVERRIDE_SRCDIR)) describe --tags --always --dirty 2>/dev/null)
endif
ifneq ($(TIMPS_GIT_DESCRIBE),)
TIMPS_BUILD_VERSION = $(TIMPS_GIT_DESCRIBE)
else
TIMPS_BUILD_VERSION = $(TIMPS_VERSION)
endif

# Submodule provides the IMP headers (ingenic-headers).
TIMPS_GIT_SUBMODULES = YES

TIMPS_DEPENDENCIES = ingenic-lib
ifeq ($(BR2_PACKAGE_OPENIMP),y)
TIMPS_DEPENDENCIES += openimp
endif
TIMPS_DEPENDENCIES += thingino-agent
ifeq ($(BR2_PACKAGE_INGENIC_SYSTEM_LIBS_NEO),y)
TIMPS_DEPENDENCIES += ingenic-system-libs-neo
endif
ifeq ($(BR2_PACKAGE_LIBAUDIOPROCESS_NEO),y)
TIMPS_DEPENDENCIES += libaudioprocess-neo
endif
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

# Audio backchannel drives the speaker via native IMP_AO now (no /bin/iac /
# ingenic-audiodaemon dependency). AAC backchannel decode IS linked, so
# libhelix-aac stays a hard dependency when it is enabled.
ifeq ($(BR2_PACKAGE_TIMPS_BC_AAC),y)
	TIMPS_DEPENDENCIES += libhelix-aac
endif

# Opus playback in the play queue links opusfile (which pulls opus + libogg).
ifeq ($(BR2_PACKAGE_TIMPS_PLAY_OPUS),y)
	TIMPS_DEPENDENCIES += opusfile
endif

# Opus as an RTSP/RTP streaming codec links the bare libopus encoder only (no
# opusfile / libogg - RTP carries raw Opus frames, no Ogg container).
ifeq ($(BR2_PACKAGE_TIMPS_STREAM_OPUS),y)
	TIMPS_DEPENDENCIES += opus
endif

# Not a link-time dependency: this is purely an ORDERING dependency for the
# TIMPS_INSTALL_WEBUI post-install hook below, which writes into thingino-
# webui's www tree. It has to land AFTER thingino-webui's own
# INSTALL_TARGET_CMDS has created the stock tree it adds to, and BEFORE
# thingino-webui's plugin-assembly finalize hook reads that tree (the assembler
# has to see files/timps.webui.json to build the nav and inject our scripts).
# Declaring the dependency makes the first half explicit instead of relying on
# package parse order; the per-package-install-before-global-finalize rule
# gives us the second half.
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
	TIMPS_DEPENDENCIES += thingino-webui
endif

# Same reasoning as thingino-webui above, for the same TIMPS_INSTALL_WEBUI
# hook's ONVIF-symlink block further down: it checks
# [ -d $(TARGET_DIR)/var/www/onvif ] before recreating image.cgi/image1.cgi,
# and under PER_PACKAGE_DIRECTORIES that directory is only visible from
# timps's own per-package view if thingino-onvif is a declared dependency -
# undeclared, the check silently fails and image1.cgi never gets created
# (image.cgi survives anyway since thingino-onvif's own INSTALL_TARGET_CMDS
# creates that one directly, independent of this hook).
ifeq ($(BR2_PACKAGE_THINGINO_ONVIF),y)
	TIMPS_DEPENDENCIES += thingino-onvif
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

ifeq ($(BR2_PACKAGE_TIMPS_BC_AAC),y)
	TIMPS_LIBS += -lhelix-aac
endif

ifeq ($(BR2_PACKAGE_TIMPS_PLAY_OPUS),y)
	TIMPS_LIBS += -lopusfile -lopus -logg
endif

ifeq ($(BR2_PACKAGE_TIMPS_STREAM_OPUS),y)
	TIMPS_LIBS += -lopus
endif

# Ingenic SDK blobs (libimp/libalog/libsysutils) reference libc symbols their
# original vendor toolchain exported that modern uClibc-ng/musl dropped (e.g.
# the glibc-2.2-era __ctype_b/__ctype_tolower bare-pointer symbols T10/T20/T21/
# T30's libalog still calls). ingenic-uclibc/ingenic-musl (already a
# TIMPS_DEPENDENCIES above) build libuclibcshim/libmuslshim to paper over
# exactly this gap - link it, same as prudynt-t does (PRUDYNT_SHIM_LIB).
# --no-as-needed/--as-needed: nothing in timps calls these symbols directly
# (only the vendor blob does), so the linker's default --as-needed would
# otherwise drop the shim from DT_NEEDED as "unused".
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	TIMPS_LIBS += -Wl,--no-as-needed -lmuslshim -Wl,--as-needed
endif
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	TIMPS_LIBS += -Wl,--no-as-needed -luclibcshim -Wl,--as-needed
endif

# USE_TRACE (src/trace.c, opt-in send-pipeline latency instrumentation) is
# deliberately NOT a BR2_PACKAGE_TIMPS_* Kconfig option - it must not be
# reachable from menuconfig. For a one-off debug build, pass TIMPS_TRACE=1 as
# a plain make-variable override on the invocation, e.g.:
#   make CAMERA=... IP=... TIMPS_TRACE=1 rebuild-timps
# Default (TIMPS_TRACE unset) is USE_TRACE=0, identical to every other build.
define TIMPS_BUILD_CMDS
	$(MAKE) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		PLATFORM=$(shell echo $(SOC_FAMILY) | tr a-z A-Z) \
		VERSION=$(TIMPS_BUILD_VERSION) \
		IMP_LIB=$(STAGING_DIR)/usr/lib \
		IMPLIBS="$(TIMPS_IMPLIBS)" \
		FAACLIB="-lfaac" \
		CFLAGS="$(TIMPS_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -L$(STAGING_DIR)/usr/lib -L$(TARGET_DIR)/usr/lib" \
		LIBS="$(TIMPS_LIBS)" \
		USE_FAAC=$(if $(BR2_PACKAGE_TIMPS_FAAC),1,0) \
		USE_TRACE=$(if $(filter 1,$(TIMPS_TRACE)),1,0) \
		USE_CONTROL=$(if $(BR2_PACKAGE_TIMPS_CONTROL),1,0) \
		USE_DAYNIGHT=$(if $(BR2_PACKAGE_TIMPS_DAYNIGHT),1,0) \
		USE_RECORD=$(if $(BR2_PACKAGE_TIMPS_RECORD),1,0) \
		USE_TIMELAPSE=$(if $(BR2_PACKAGE_TIMPS_TIMELAPSE),1,0) \
		USE_TLS=$(if $(BR2_PACKAGE_TIMPS_TLS),1,0) \
		USE_SRT=$(if $(BR2_PACKAGE_TIMPS_SRT),1,0) \
		USE_ROTATE=$(if $(BR2_PACKAGE_TIMPS_ROTATE),1,0) \
		USE_SW_ROTATE=$(if $(BR2_PACKAGE_TIMPS_SW_ROTATE),1,0) \
		USE_OSD_HINTING=$(if $(BR2_PACKAGE_TIMPS_OSD_HINTING),1,0) \
		USE_BACKCHANNEL=$(if $(BR2_PACKAGE_TIMPS_BACKCHANNEL),1,0) \
		USE_BC_AAC=$(if $(BR2_PACKAGE_TIMPS_BC_AAC),1,0) \
		HELIXLIB="-lhelix-aac" \
		HELIX_INC=$(STAGING_DIR)/usr/include \
		USE_PLAY=$(if $(BR2_PACKAGE_TIMPS_PLAY),1,0) \
		USE_PLAY_OPUS=$(if $(BR2_PACKAGE_TIMPS_PLAY_OPUS),1,0) \
		OPUSLIB="-lopusfile -lopus -logg" \
		OPUS_INC=$(STAGING_DIR)/usr/include \
		USE_STREAM_OPUS=$(if $(BR2_PACKAGE_TIMPS_STREAM_OPUS),1,0) \
		OPUS_ENC_LIB="-lopus" \
		-C $(@D) target
endef

define TIMPS_INSTALL_TARGET_CMDS
	# Install the thingino-agent backend adapter at the fixed path, overwriting
	# the null fallback installed by thingino-agent.
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/agent-adapter \
		$(TARGET_DIR)/usr/libexec/agent/adapter.sh

	# Install the streamer binary
	$(INSTALL) -D -m 0755 $(@D)/timpsd \
		$(TARGET_DIR)/usr/bin/timpsd

	# Install default configuration file
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/timps.conf \
		$(TARGET_DIR)/etc/timps.conf

	# One template for every board means every other sensor warns once per
	# start. Buildroot knows the right name - the kernel driver is built from
	# it. i2c_addr stays as shipped: buildroot does not carry it, and
	# /proc/jz/sensor supplies it wherever that exists.
	if [ -n "$(call qstrip,$(BR2_SENSOR_1_NAME))" ]; then \
		$(SED) 's|^sensor.model .*|sensor.model    = $(call qstrip,$(BR2_SENSOR_1_NAME))|' \
			$(TARGET_DIR)/etc/timps.conf; \
	fi

	# Install init script
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/S95timps \
		$(TARGET_DIR)/etc/init.d/S95timps

	# Install TLS certificate generation script if TLS is enabled
	if [ "$(BR2_PACKAGE_TIMPS_TLS)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/generate-tls-certs.sh \
			$(TARGET_DIR)/usr/bin/generate-timps-tls-certs.sh; \
	fi

	# Install the self-test helper
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/timps-irprobe \
		$(TARGET_DIR)/usr/bin/timps-irprobe

	# Diagnostic helpers: nothing on the camera calls them, and the two
	# collectors only pay off where something gathers what they emit.
	# /usr/bin rather than an /etc overlay - squashfs compresses and
	# deduplicates, the writable jffs2 does neither.
	if [ "$(BR2_PACKAGE_TIMPS_DIAG_TOOLS)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/timps-dn-isp-log \
			$(TARGET_DIR)/usr/bin/timps-dn-isp-log; \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/timps-logcat-ship \
			$(TARGET_DIR)/usr/bin/timps-logcat-ship; \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/timps-selftest.sh \
			$(TARGET_DIR)/usr/bin/timps-selftest; \
	fi

	# System-sound play wrapper: enqueues PLAY/STOP onto timps's /run/timps/
	# audio_out FIFO (native IMP_AO). Same interface prudynt/raptor ship, so the
	# WiFi-portal / sysupgrade-chime / ESPHome media_player integrations that
	# shell out to `play` work on a timps image too.
	if [ "$(BR2_PACKAGE_TIMPS_PLAY)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/play \
			$(TARGET_DIR)/usr/sbin/play; \
	fi

	# Motion->send2 bridge. timps.conf's motion.on_motion points at this path, so
	# install it unconditionally: otherwise imp_motion.c runs system() on a
	# missing script on every motion event. It no-ops cleanly when the send2
	# toolkit/config are absent (the send2 hook below adds those when WEBUI is on).
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/timps-motion \
		$(TARGET_DIR)/usr/sbin/timps-motion

	# Install the day/night ISP hook (/usr/sbin/color) when native day/night
	# detection is enabled; timps calls it to drive the ircut/light/gain
	# switching through thingino's daynight scripts.
	if [ "$(BR2_PACKAGE_TIMPS_DAYNIGHT)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/color \
			$(TARGET_DIR)/usr/sbin/color; \
	fi

	$(TIMPS_INSTALL_DAYNIGHT_SCRIPTS)
endef

# NOTE: board day/night hardware scripts (/usr/sbin/{daynight,ircut,light}).
# These are thingino's shared userspace hardware drivers - daynight's own
# header says "called by streamers (prudynt, raptor, daynightd)" - but they
# physically live in package/thingino-daynightd/files/, and
# BR2_PACKAGE_THINGINO_DAYNIGHTD is selected by exactly ONE Kconfig symbol:
# BR2_PACKAGE_THINGINO_STREAMER_PRUDYNT. So on a clean timps image none of
# them are built or installed, and the whole day/night hook chain dead-ends:
#
#   timps daynight thread -> execlp("daynight", "night") -> rc=127
#
# Live incident (Garage, T31/SC4336P, 2026-08-12): timps's own detection was
# working perfectly ("[DAYNIGHT] switching to night (total_gain 3557)") but
# every switch_cmd invocation failed with rc=127, so the IR-cut filter was
# never removed and the IR illuminator never lit. The sensor kept ramping
# total_gain (3500 -> 22000+ over minutes) trying to expose a scene it could
# not see through the IR-cut filter, and the image went purple/IR-tinted -
# the same ISP-vs-board desync failure mode as forcing running_mode by hand,
# reached from the other direction: here NOTHING drove the board hardware.
#
# Installing only `daynight` would NOT have fixed it: the script guards every
# hardware step with command_present, so with ircut/light also absent it would
# have exited 0 having done nothing but call `color` - an ISP-only flip, i.e.
# exactly the purple image again, just silently. All three go together.
#
# ircut and light are installed UNCONDITIONALLY (not gated on TIMPS_DAYNIGHT):
# timps's own WebUI bridge files/www/x/json-imp.cgi shells out to both for the
# control-bar IR-cut / IR-LED buttons, so they are needed on any timps image
# with the WebUI regardless of who does the day/night detection.
#
# S06ircut latches the IR-cut relay to its day position at boot. It matters on
# a timps image because timps starts in DN_UNKNOWN and ADOPTS the persisted
# ISP running_mode without re-issuing switch_cmd (see daynight.c's dead-zone
# adoption note): a camera that shut down at night and boots in daylight would
# otherwise keep the relay latched open all day with the ISP in colour mode -
# purple image, and no gain excursion to trigger a corrective switch. It is a
# one-shot boot-time latch at S06, long before S95timps, so it does not fight
# timps's detection thread. Gated with the detection thread, since an image
# using an external photosensing solution should let that solution own it.
#
# Installed straight from thingino-daynightd's PKGDIR rather than copied into
# package/timps/files/: these are plain shell scripts with no build step, so
# there is a single source of truth and nothing to drift. This is the same
# pattern TIMPS_INSTALL_SEND2 below already uses to ship prudynt-t's send2*
# tools without enabling the prudynt-t package, and $(2)_PKGDIR is assigned
# unconditionally by inner-generic-package (pkg-generic.mk), independent of
# whether the package is selected. When thingino-daynightd IS selected (a
# stale =y carried across oldconfig), it installs byte-identical copies of
# these same files, so the two paths cannot disagree.
define TIMPS_INSTALL_DAYNIGHT_SCRIPTS
	$(INSTALL) -D -m 0755 $(THINGINO_DAYNIGHTD_PKGDIR)/files/ircut \
		$(TARGET_DIR)/usr/sbin/ircut
	$(INSTALL) -D -m 0755 $(THINGINO_DAYNIGHTD_PKGDIR)/files/light \
		$(TARGET_DIR)/usr/sbin/light
	if [ "$(BR2_PACKAGE_TIMPS_DAYNIGHT)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_DAYNIGHTD_PKGDIR)/files/daynight \
			$(TARGET_DIR)/usr/sbin/daynight; \
		$(INSTALL) -D -m 0755 $(THINGINO_DAYNIGHTD_PKGDIR)/files/S06ircut \
			$(TARGET_DIR)/etc/init.d/S06ircut; \
	fi
endef

# NOTE: WebUI. timps is a thingino-webui PLUGIN: files/timps.webui.json is
# installed into /var/www/a/plugins/ and thingino-webui's assemble_plugins.py
# finalize hook does the rest - it merges our "nav" contributions into the
# menu, injects our "scripts"/"styles" into every page, and records the
# "timps" feature flag (the assembler already knows that flag and exempts
# mutually exclusive streamers from page/CGI overlap checks - see
# STREAMER_FEATURE_FLAGS in package/thingino-webui/scripts/assemble_plugins.py).
# This mirrors prudynt-t/files/prudynt.webui.json, which made the same
# transition on 2026-08-16, and the eleven other packages that ship a manifest.
#
# WHAT THAT REPLACED (2026-08, this commit): timps used to install FORKED
# copies of five thingino-webui files - a/navigation.js, a/main.js, a/main.css,
# a/footer.js and a/preview.js - plus same-named replacements for x/json-imp.cgi
# and both heartbeat CGIs, and ~40 lines of ordering machinery here to make
# them stick. They are gone:
#   a/navigation.js  -> the "nav" section of timps.webui.json. The fork was a
#                       frozen snapshot of the WHOLE menu, including entries
#                       owned by other packages (Doorbell Chime, GPIO pins,
#                       Home Assistant, MQTT Subscriptions, Pan/Tilt motors),
#                       every one of which now declares itself in its own
#                       manifest - so the snapshot could only ever go stale.
#   a/main.js        -> a/timps-control-bar.js, declared in "scripts". It
#                       overrides the six control-bar actions on the global
#                       object after core main.js has evaluated; see that
#                       file's header for why that is well-defined. The fork
#                       had drifted: it had LOST core's apiFetch()/
#                       API_KEY_PROMISE helpers and carried wyze-accessory's
#                       doorbell banner (that package ships it now).
#   a/main.css       -> a/timps.css, declared in "styles".
#   a/footer.js      -> nothing. Its only change was an empty <div
#                       id="footer-timps-version"> slot, and a/timps-version.js
#                       already falls back to its own corner badge when that
#                       slot is absent.
#   a/preview.js     -> renamed a/timps-preview.js (only timps's own pages load
#                       it; it is an unrelated script to core's preview.js).
#   x/json-imp.cgi   -> renamed x/timps-imp.cgi (its only two callers are
#                       overridden in a/timps-control-bar.js).
# Each of those was a path that thingino-webui also ships, and every such
# collision is what the machinery existed for - see TIMPS_REAPPLY_WEBUI_OVERLAY
# below, which is all that is left of it.
#
# The bridge CGIs that remain are timps-flavored translations of the prudynt-
# shaped requests the stock pages make (/x/restart-prudynt.cgi, the snapshot
# CGIs), targeting timps's /control JSON API on 127.0.0.1:8880, plus the native
# page scripts (files/www/a/) and pages (files/www/*.html).
#
# The whole www/x directory is installed (CGIs and the .sh lib alike; the
# webserver executes anything under the /x/ CGI prefix regardless of extension
# - uhttpd via "-x /x", busybox httpd via its /x/ convention). The WebUI's own
# prudynt-flavored bridge CGIs (they shell out to the absent prudyntctl) are
# purged so a timps image carries no dead endpoints.
#
# Snapshots: files/www/x/ch0.jpg is a timps-flavored snapshot CGI installed
# under four names (ch0/ch1 inline, dl0/dl1 download - see the script header);
# /var/www/onvif/image[1].cgi are symlinks into /x/ so ONVIF snapurls work.
# This mirrors stock thingino-onvif's "ln -sf /var/www/x/ch0.jpg image.cgi"
# pattern, the ONLY snapshot mechanism that works on uhttpd: uhttpd resolves
# the symlink to a physical path under its /x CGI prefix and executes it,
# whereas a script placed directly in /var/www/onvif/ would be served as a
# static file, and busybox-httpd "P:" proxy lines in /etc/httpd.conf are
# simply ignored (uhttpd never reads that file). The old "/mjpeg" busybox
# proxy alias is dropped for the same reason; nothing references it anymore
# (the preview streams :8880/stream.mp4 and :8880/stream.mjpeg directly).
#
# Unlike prudynt-t.mk, which lists every www file on its own $(INSTALL) line,
# the three loops below glob the directories: timps ships 45 www files to
# prudynt's 30 and every one of them is unconditional, so a glob cannot fall
# out of sync with the tree the way a hand-maintained list does. Everything
# else about the install follows prudynt's shape, manifest included.
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI)$(BR2_PACKAGE_TIMPS_CONTROL),yy)
define TIMPS_INSTALL_WEBUI
	# WebUI plugin manifest - nav entries, global script/style injection,
	# the "timps" feature flag, and the page/CGI claims used for conflict
	# detection across plugins.
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/timps.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/timps.webui.json
	# x/ = the structural CGIs (token, restart, GPIO bridge, heartbeat);
	# a/ = the native page scripts; *.html = the pages.
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
	rm -f $(TARGET_DIR)/var/www/x/ch0.mjpg $(TARGET_DIR)/var/www/x/ch1.mjpg
	# CAVEAT on the two rm -f above (measured 2026-08-19, flash-headroom audit):
	# deleting from THIS tree only works for a path thingino-webui no longer
	# ships at all - which is true of all nine paths listed here, so they are
	# effectively no-ops kept as documentation. It does NOT work for a stock
	# file that still exists: this hook runs in timps's PER-PACKAGE tree, and
	# the global merge then rsyncs a pristine copy back in from every other
	# package that inherited thingino-webui's www tree (verified: preview.js
	# survives here via thingino-gpio, thingino-mosquitto-20x, thingino-motors,
	# thingino-webui and wireguard-tools). That is the delete-side of exactly
	# the same per-package-merge problem the big comment above documents for
	# the install side. A live stock file has to be removed from the global
	# TARGET_FINALIZE phase instead - see TIMPS_PURGE_STOCK_WEBUI below.
	# Snapshot CGIs: the x/ loop above already replaced the stock prudynt
	# x/ch0.jpg with timps's loopback-fetch script; clone it to the other
	# three names the WebUI expects (channel/disposition are derived from the
	# invoked name, so the copies are byte-identical). This also replaces the
	# stock prudynt dl0/dl1.jpg download CGIs.
	for n in ch1.jpg dl0.jpg dl1.jpg ; do \
		$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/www/x/ch0.jpg \
			$(TARGET_DIR)/var/www/x/$$n ; \
	done
	# ONVIF snapshot URLs: recreate thingino-onvif's stock symlink (an earlier
	# timps revision deleted it) and add the ch1 counterpart, since timps's
	# S96onvif_discovery publishes /onvif/image.cgi AND /onvif/image1.cgi as
	# the per-profile snapurls. Symlink-into-/x is what makes uhttpd execute
	# them as CGIs (see the NOTE above). Only when ONVIF is in the image.
	if [ -d $(TARGET_DIR)/var/www/onvif ]; then \
		ln -sf /var/www/x/ch0.jpg $(TARGET_DIR)/var/www/onvif/image.cgi ; \
		ln -sf /var/www/x/ch1.jpg $(TARGET_DIR)/var/www/onvif/image1.cgi ; \
	fi
endef
TIMPS_POST_INSTALL_TARGET_HOOKS += TIMPS_INSTALL_WEBUI

# WHAT IS LEFT OF THE OLD ORDERING MACHINERY, and why it cannot go yet.
#
# The plugin manifest can ADD to the WebUI (nav items, global scripts, styles,
# preview-body/script injection). It cannot REPLACE a file thingino-webui
# itself ships: assemble_plugins.py's "pages" and "cgi" lists are validation
# only - it reads them to detect two plugins claiming the same path and
# installs nothing (verified against the script; only "nav", "scripts",
# "styles", "preview.*" and "featureFlags" have runtime effect). Five timps
# files still have to win over a same-named thingino-webui file:
#
#   preview.html            a whole custom page (native MSE/fMP4 player against
#                           :8880/stream.mp4, plus a Statistics card fed by
#                           timps's /events SSE). The manifest's preview.html
#                           key is a SNIPPET substituted for the
#                           THINGINO_PLUGIN_PREVIEW_BODY marker inside core's
#                           page, not a replacement page, and core's page also
#                           loads core's a/preview.js (prudynt bridge CGIs) -
#                           so injection cannot express this one.
#   tool-sensor-data.html   timps's sensor chart reads timps's own /events
#   a/tool-sensor-data.js   "daynight" stream and /x/json-config-daynight.cgi;
#                           core's reads daynightd's history/sensors CGIs,
#                           which do not exist here. Core's script is a
#                           self-invoking IIFE, so it cannot be overridden the
#                           way a/timps-control-bar.js overrides main.js.
#   x/json-heartbeat.cgi    core main.js hardcodes both URLs in top-level
#   x/json-heartbeat-slow.cgi `const`s (HeartBeatEndpoint / SlowHeartbeat-
#                           Endpoint), which are NOT reachable on the global
#                           object, so a plugin script cannot re-point them.
#                           Core's heartbeat-lib.sh has a raptor path and a
#                           prudynt/daynightd path and no timps path at all.
#
# And a same-named file needs help, because with BR2_PER_PACKAGE_DIRECTORIES=y
# (configs/fragments/core.fragment) every package installs into its own
# per-package/<pkg>/target/ copy, seeded by rsyncing in the per-package trees of
# its dependencies. So every package that (transitively) depends on
# thingino-webui carries a PRISTINE copy of the whole stock www tree - not just
# thingino-webui itself. Buildroot's target-finalize merges them all into the
# real $(TARGET_DIR) with (buildroot/package/pkg-utils.mk, per-package-rsync,
# "copy" variant):
#
#     printf "%s/target/\n" $(sort $(PACKAGES)) | tac \
#         | rsync -a --hard-links --files-from=- --no-R -r $(PER_PACKAGE_DIR) ...
#
# rsync de-duplicates its file list keeping the FIRST occurrence, and `tac`
# reverses the alphabetically sorted package list - so for a colliding path the
# alphabetically LAST package wins. "timps" only beats packages sorting before
# it; wireguard-tools (verified: its per-package/wireguard-tools/target/ carries
# an inherited pristine var/www/a/*) hands the merge the stock file, which
# lands in $(TARGET_DIR) and silently reverts the overlay. Nothing in the build
# fails; the per-package tree is correct, only the merged one is not.
#
# So the five files are re-installed from the GLOBAL target-finalize phase,
# after that merge and before thingino-webui's plugin assembly. The hook is
# PREPENDED to TARGET_FINALIZE_HOOKS: thingino-webui.mk is parsed first
# (alphabetical glob), so its ASSEMBLE_PLUGINS hook is already in the list by
# the time this file is parsed, and prepending is what puts us in front of it -
# so the two HTML pages we re-install still get the plugin layer
# (<script src="/a/plugins.js">, our injected scripts/styles, the preview body).
# $(TARGET_DIR) resolves to the real target tree at global finalize (PKG is
# unset); the body is idempotent. TIMPS_INSTALL_WEBUI above already put these
# files in timps's own per-package tree, which is what keeps them attributed to
# timps in .files-list.txt.
#
# To retire this hook entirely, upstream needs a way for a manifest to claim
# ownership of a core page/CGI (i.e. make "pages"/"cgi" install-and-win rather
# than validate-only). Until then, keep this list SHORT: anything added here is
# a new fork of a thingino-webui file, which is exactly what this package just
# spent a rewrite getting rid of.
define TIMPS_REAPPLY_WEBUI_OVERLAY
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/www/preview.html \
		$(TARGET_DIR)/var/www/preview.html
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/www/tool-sensor-data.html \
		$(TARGET_DIR)/var/www/tool-sensor-data.html
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/www/a/tool-sensor-data.js \
		$(TARGET_DIR)/var/www/a/tool-sensor-data.js
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/www/x/json-heartbeat.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat.cgi
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/www/x/json-heartbeat-slow.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat-slow.cgi
endef

# The delete-side counterpart, and the only place a LIVE thingino-webui file
# can actually be removed (see the CAVEAT in TIMPS_INSTALL_WEBUI above): the
# global TARGET_FINALIZE phase, after the per-package merge has put every
# inherited pristine copy into the real $(TARGET_DIR).
#
# Both entries are stock scripts the preview swap orphaned. Neither has a
# caller anywhere in the MERGED /var/www - checked against the built tree, not
# against this package's own files:
#   a/preview.js    thingino-webui's stock streamer preview, driving the
#                   prudynt bridge CGIs. TIMPS_REAPPLY_WEBUI_OVERLAY above
#                   replaces preview.html wholesale with the native MSE/fMP4
#                   page, which loads a/timps-preview.js instead. No
#                   <script src="/a/preview.js"> survives on a timps image;
#                   the only remaining mention is prose in a comment.
#   a/sei-rotate.js referenced only from prudynt-t's and thingino-raptor's
#                   streamer-*.html. "Streamer" is a Kconfig choice
#                   (package/thingino-streamer/Config.in), so neither package
#                   can be installed next to timps and neither page can exist
#                   here. The script also early-returns on /preview.html.
#
# Worth 39.4 KB uncompressed but only 4096 bytes off the packed image
# (measured: rootfs.squashfs 5246976 -> 5242880, -b 256K -comp xz). JS
# compresses about tenfold and squashfs pads to 4K, so uncompressed script
# sizes overstate the win by roughly an order of magnitude - do not size
# future www cleanups off `du`.
define TIMPS_PURGE_STOCK_WEBUI
	rm -f $(TARGET_DIR)/var/www/a/preview.js \
	      $(TARGET_DIR)/var/www/a/sei-rotate.js
endef
TARGET_FINALIZE_HOOKS := TIMPS_REAPPLY_WEBUI_OVERLAY $(TARGET_FINALIZE_HOOKS)
TARGET_FINALIZE_HOOKS += TIMPS_PURGE_STOCK_WEBUI
endif

# NOTE: motors-detection fix. Stock S48webui-config reports
# window.thinginoUIConfig.device.motors=true whenever /etc/thingino.json HAS a
# "motors" key at all - but configs/common.thingino.json ships one on every
# board (empty gpio_pan/gpio_tilt, a disabled-by-default placeholder), so any
# board without its OWN motors override (i.e. every non-PTZ camera) still
# shows the preview page's PTZ joystick overlay. Our copy checks the actual
# GPIO pins are configured instead. Independent of TIMPS_CONTROL - it's about
# the preview page in general, not the /control API - so only gated on the
# WebUI being present at all (nothing to override otherwise).
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
define TIMPS_INSTALL_WEBUI_CONFIG_FIX
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/S48webui-config \
		$(TARGET_DIR)/etc/init.d/S48webui-config
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_INSTALL_WEBUI_CONFIG_FIX
endif

# NOTE: send-to-* notification toolkit now lives in package/thingino-send2.
# Timps ships its own send2common (timps-only snapshot/clip via /control) and
# telegram-cam-register overlay via a finalize hook so they win over the shared
# prudynt default regardless of build order. Gated on TIMPS_CONTROL: timps-motion
# and send2common POST to timps's /control endpoint.
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI)$(BR2_THINGINO_DEV_IPCAM)$(BR2_PACKAGE_TIMPS_CONTROL),yyy)
THINGINO_SEND2_FILES_DIR = $(THINGINO_SEND2_PKGDIR)/files
define TIMPS_INSTALL_SEND2
	$(INSTALL) -D -m 0644 $(THINGINO_SEND2_FILES_DIR)/prudynt-helpers \
		$(TARGET_DIR)/usr/share/prudynt-helpers
	$(INSTALL) -D -m 0644 $(TIMPS_PKGDIR)/files/send2common \
		$(TARGET_DIR)/usr/share/send2common
	$(INSTALL) -D -m 0755 $(TIMPS_PKGDIR)/files/telegram-cam-register \
		$(TARGET_DIR)/usr/sbin/telegram-cam-register
	for f in send2email send2ftp send2ntfy send2storage send2telegram send2webhook; do \
		$(INSTALL) -D -m 0755 $(THINGINO_SEND2_FILES_DIR)/$$f $(TARGET_DIR)/usr/sbin/$$f ; \
	done
	[ -f $(TARGET_DIR)/etc/send2.json ] || \
		$(INSTALL) -D -m 0644 $(THINGINO_SEND2_FILES_DIR)/send2.json \
			$(TARGET_DIR)/etc/send2.json
endef
TIMPS_TARGET_FINALIZE_HOOKS += TIMPS_INSTALL_SEND2
endif

# NOTE: preview page. timps ships its own self-contained MSE/fMP4 preview
# (it fetches :8880/stream.mp4) as files/www/preview.html - same filename as
# core webui's. It is one of the five files in TIMPS_REAPPLY_WEBUI_OVERLAY
# above; see the rationale there for why the plugin manifest cannot express a
# whole replacement page and this one still needs the overlay. Implicitly
# gated on TIMPS_CONTROL through the install block's own gate: preview.html
# pulls /x/timps-token.cgi, which only exists when that gate is satisfied.

# NOTE: native day/night. When timps detects day/night itself
# (BR2_PACKAGE_TIMPS_DAYNIGHT), none of thingino-daynightd's autostart entry
# points must run - not just the main daemon (it would double-switch against
# timps's own detection thread) but also its dusk2dawn scheduler, which drives
# the same IR-cut/illuminator hardware off a sunrise/sunset clock. Done as a
# finalize hook so it wins regardless of package build order; idempotent, a
# no-op when absent.
#
# thingino-daynightd can end up selected on a timps image even though only
# BR2_PACKAGE_THINGINO_STREAMER_PRUDYNT selects it in Config.in, because
# BR2_PACKAGE_THINGINO_DAYNIGHTD carries no "depends on" of its own and Kconfig
# happily keeps a previously-set =y across oldconfig - so this cleanup has to
# keep working.
#
# The init script names are matched by GLOB. thingino-daynightd's 2.0.0 rewrite
# renamed S97daynightd -> S10daynightd and this hook was not updated with it,
# so for that whole period it removed a file that no longer existed and the
# daemon would have autostarted anyway on any image that had it. A glob does
# not silently rot the next time upstream renumbers a runlevel.
#
# S06ircut is deliberately NOT removed: it is a one-shot boot-time IR-cut
# relay latch, not an autostart daemon, and TIMPS_INSTALL_DAYNIGHT_SCRIPTS
# above installs it on purpose (see the rationale there).
#
# The WebUI "Photosensing" page is deliberately KEPT: files/www/a/
# config-photosensing.js is a timps-native overlay that talks straight to
# /control (daynight.enabled / daynight.total_gain_{night,day}_threshold - see
# its header) and is the config UI for timps's own detection, NOT the stock
# page that drove daynightd. Earlier revisions of this hook deleted the page and
# tried to strip its nav entry; that left the control-bar.js "Photosensing
# Config" link (shipped unchanged from thingino-webui) pointing at a removed
# page, so it dead-ended on Preview. Keeping the page - installed by
# TIMPS_INSTALL_WEBUI above, with its menu entry contributed by the "nav"
# section of files/timps.webui.json - makes that link resolve correctly.
# (The page's Controls/Schedule columns still use the board daynight script's
# legacy /x/json-config-daynight.cgi best-effort; absent-CGI is handled in-page.)
#
# This is also why files/timps.webui.json deliberately does NOT list
# /config-photosensing.html (nor /config-privacy.html) in its "pages" array:
# thingino-daynightd and thingino-privacy-lite claim those paths in their own
# manifests, neither is mutually exclusive with timps (as this very hook shows,
# daynightd can still be selected on a timps image), and assemble_plugins.py's
# streamer exemption only covers two plugins that both carry a STREAMER_FEATURE
# FLAG. Claiming them would turn a today-silent file collision into a hard build
# failure for those configurations. The nav entries ARE contributed, because the
# page has to stay reachable; on a combined image the entry can appear twice.
ifeq ($(BR2_PACKAGE_TIMPS_DAYNIGHT),y)
define TIMPS_DISABLE_DAYNIGHTD
	rm -f $(TARGET_DIR)/etc/init.d/*daynightd \
		$(TARGET_DIR)/etc/init.d/*dusk2dawn
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
