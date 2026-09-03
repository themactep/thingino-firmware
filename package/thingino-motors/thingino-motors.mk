# Fork (WebSocket PTZ, not yet upstream) when WS is wanted or timps is the
# streamer; upstream otherwise. Keyed on timps too so a timps build never
# falls back to plain upstream just because the WS toggle is stale/off - but
# not on a DW9714-only build, where WS is unavailable anyway (Config.in's
# !DW9714_ONLY depends on), so there's nothing to gain from the fork there.
THINGINO_MOTORS_SITE_METHOD = git
ifneq ($(filter y,$(BR2_PACKAGE_THINGINO_MOTORS_WS) $(if $(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),,$(BR2_PACKAGE_THINGINO_STREAMER_TIMPS))),)
THINGINO_MOTORS_SITE = https://github.com/Lu-Fi/thingino-motors.git
THINGINO_MOTORS_SITE_BRANCH = thingino-motors-websocket
THINGINO_MOTORS_VERSION = caa4bf3d9f5a9fb8b72f8e0d42bd044177dfeb56
else
THINGINO_MOTORS_SITE = https://github.com/thingino/thingino-motors.git
THINGINO_MOTORS_SITE_BRANCH = main
THINGINO_MOTORS_VERSION = dcfdc27473d23a528e7bb57407fbc242de9b7053
endif
THINGINO_MOTORS_LICENSE = MIT
THINGINO_MOTORS_LICENSE_FILES = LICENSE

THINGINO_MOTORS_DEPENDENCIES += thingino-jct

# `motors --version` and the "version" key in `motors -j` answer "which build
# is this camera actually running" - snapshot with := here, because
# $(eval $(generic-package)) below rewrites THINGINO_MOTORS_VERSION to the
# literal "custom" whenever an OVERRIDE_SRCDIR is set.
THINGINO_MOTORS_PINNED_VERSION := $(THINGINO_MOTORS_VERSION)
ifneq ($(call qstrip,$(THINGINO_MOTORS_OVERRIDE_SRCDIR)),)
THINGINO_MOTORS_GIT_DESCRIBE := $(shell git -C $(call qstrip,$(THINGINO_MOTORS_OVERRIDE_SRCDIR)) describe --tags --always --dirty 2>/dev/null)
endif
ifneq ($(THINGINO_MOTORS_GIT_DESCRIBE),)
THINGINO_MOTORS_BUILD_VERSION = $(THINGINO_MOTORS_GIT_DESCRIBE)
else
THINGINO_MOTORS_BUILD_VERSION = $(THINGINO_MOTORS_PINNED_VERSION)
endif
# Single quotes make it survive as a C string literal through the recipe.
THINGINO_MOTORS_VERSION_DEF = -DMOTORS_BUILD_VERSION='"$(THINGINO_MOTORS_BUILD_VERSION)"'

# Compiled directly via $(TARGET_CC); SRCS/LIBS/DEFS collect what WS/TLS add.
# $(@D) is only valid in a recipe, so these stay recursively expanded (+=).
THINGINO_MOTORS_DAEMON_SRCS = $(@D)/src/motor-daemon.c
THINGINO_MOTORS_DAEMON_LIBS = -ljct -lm
THINGINO_MOTORS_DAEMON_DEFS =

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_WS),y)
THINGINO_MOTORS_DAEMON_SRCS += \
	$(@D)/src/sha1.c \
	$(@D)/src/sha256.c \
	$(@D)/src/ws.c \
	$(@D)/src/ws_token.c \
	$(@D)/src/motor-ws.c
THINGINO_MOTORS_DAEMON_LIBS += -lpthread
# motor-daemon.c starts the listener only under #ifdef MOTORS_WS.
THINGINO_MOTORS_DAEMON_DEFS += -DMOTORS_WS

# Nested in WS: TLS wraps the listener, nothing to wrap without it.
ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_WS_TLS),y)
THINGINO_MOTORS_DEPENDENCIES += mbedtls
THINGINO_MOTORS_DAEMON_SRCS += $(@D)/src/ws_tls.c
# libmbedx509/libmbedcrypto too: --gc-sections won't pull them in transitively.
THINGINO_MOTORS_DAEMON_LIBS += -lmbedtls -lmbedx509 -lmbedcrypto
THINGINO_MOTORS_DAEMON_DEFS += -DMOTORS_WS_TLS
endif
endif

define THINGINO_MOTORS_INSTALL_JSON_CMDS
	# Stage defaults for later merge by thingino-core
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/motors.json \
		$(TARGET_DIR)/usr/share/thingino-defaults/30-motors.json
endef

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),y)
define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/dw9714-ctrl \
		$(TARGET_DIR)/usr/sbin/dw9714-ctrl

	$(THINGINO_MOTORS_INSTALL_JSON_CMDS)
endef
else

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
# Web pages must be installed after thingino-webui so that the
# plugin assembly finalize hook discovers the motors manifest.
THINGINO_MOTORS_DEPENDENCIES += thingino-webui

define THINGINO_MOTORS_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/config-motors.html \
		$(TARGET_DIR)/var/www/config-motors.html
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/a/config-motors.js \
		$(TARGET_DIR)/var/www/a/config-motors.js
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/a/preview-motors.js \
		$(TARGET_DIR)/var/www/a/preview-motors.js
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/a/preview-motors-settings.js \
		$(TARGET_DIR)/var/www/a/preview-motors-settings.js
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motor.cgi \
		$(TARGET_DIR)/var/www/x/json-motor.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motor-params.cgi \
		$(TARGET_DIR)/var/www/x/json-motor-params.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motor-stream.cgi \
		$(TARGET_DIR)/var/www/x/json-motor-stream.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motors-config.cgi \
		$(TARGET_DIR)/var/www/x/json-motors-config.cgi

	# Install plugin manifest for build-time assembly by thingino-webui
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/motors.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/motors.webui.json
endef
endif

# -ffunction-sections/-fdata-sections + --gc-sections: per-function dead-code
# stripping. Measured -7680 B (-12.2%) on the WS build.
define THINGINO_MOTORS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s -ffunction-sections -fdata-sections $(THINGINO_MOTORS_VERSION_DEF) $(@D)/src/motor.c -o $(@D)/motors -ljct -Wl,--gc-sections
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s -ffunction-sections -fdata-sections $(THINGINO_MOTORS_DAEMON_DEFS) $(THINGINO_MOTORS_DAEMON_SRCS) -o $(@D)/motors-daemon $(THINGINO_MOTORS_DAEMON_LIBS) -Wl,--gc-sections
endef

define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/motors \
		$(TARGET_DIR)/usr/bin/motors

	$(INSTALL) -D -m 0755 $(@D)/motors-daemon \
		$(TARGET_DIR)/usr/bin/motors-daemon

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/S59motor \
		$(TARGET_DIR)/etc/init.d/S59motor

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets \
		$(TARGET_DIR)/usr/sbin

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/ptz-ctrl \
		$(TARGET_DIR)/usr/sbin/ptz-ctrl

	$(THINGINO_MOTORS_INSTALL_JSON_CMDS)

	$(THINGINO_MOTORS_INSTALL_WWW_CMDS)
endef
endif

$(eval $(generic-package))
