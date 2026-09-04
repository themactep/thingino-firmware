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

define THINGINO_MOTORS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/src/motor.c -o $(@D)/motors -ljct
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/src/motor-daemon.c -o $(@D)/motors-daemon -ljct -lm
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
