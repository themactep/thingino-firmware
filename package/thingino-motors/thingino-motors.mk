THINGINO_MOTORS_SITE_METHOD = git
THINGINO_MOTORS_SITE = https://github.com/themactep/thingino-motors.git
THINGINO_MOTORS_SITE_BRANCH = master
THINGINO_MOTORS_VERSION = 10c46de54c07de903d9b72e3d784e74e8981aad4
THINGINO_MOTORS_LICENSE = MIT
THINGINO_MOTORS_LICENSE_FILES = LICENSE

THINGINO_MOTORS_DEPENDENCIES += host-thingino-jct thingino-jct

define THINGINO_MOTORS_INSTALL_JSON_CMDS
	# Import base motors defaults into thingino.json
	if [ -f "$(THINGINO_MOTORS_PKGDIR)/files/motors.json" ] && [ -f "$(TARGET_DIR)/etc/thingino.json" ]; then \
		$(HOST_DIR)/bin/jct "$(TARGET_DIR)/etc/thingino.json" import "$(THINGINO_MOTORS_PKGDIR)/files/motors.json"; \
	fi

	# Apply user motors overrides
	if [ -n "$(THINGINO_USER_MOTORS_JSON_FILES)" ]; then \
		if [ ! -x "$(HOST_DIR)/bin/jct" ]; then \
			echo "ERROR: host jct tool missing: $(HOST_DIR)/bin/jct"; \
			exit 1; \
		fi; \
	fi
	for USER_MOTORS_CONFIG in $(THINGINO_USER_MOTORS_JSON_FILES); do \
		if [ -s "$$USER_MOTORS_CONFIG" ]; then \
			echo "Applying user motors override from $$USER_MOTORS_CONFIG"; \
			echo "$(HOST_DIR)/bin/jct $(TARGET_DIR)/etc/thingino.json import \"$$USER_MOTORS_CONFIG\""; \
			$(HOST_DIR)/bin/jct "$(TARGET_DIR)/etc/thingino.json" import "$$USER_MOTORS_CONFIG"; \
		fi; \
	done
endef

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),y)
define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/dw9714-ctrl \
		$(TARGET_DIR)/usr/sbin/dw9714-ctrl

	$(THINGINO_MOTORS_INSTALL_JSON_CMDS)
endef
else

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
# Web pages must be installed after thingino-webui so that the navigation
# and preview markers exist and asset tags can be re-applied on top.
THINGINO_MOTORS_DEPENDENCIES += thingino-webui

define THINGINO_MOTORS_INSTALL_WWW_CMDS
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/config-motors.html \
		$(TARGET_DIR)/var/www/config-motors.html
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/a/config-motors.js \
		$(TARGET_DIR)/var/www/a/config-motors.js
	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/www/a/preview-motors.js \
		$(TARGET_DIR)/var/www/a/preview-motors.js
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motor.cgi \
		$(TARGET_DIR)/var/www/x/json-motor.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motor-params.cgi \
		$(TARGET_DIR)/var/www/x/json-motor-params.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motor-stream.cgi \
		$(TARGET_DIR)/var/www/x/json-motor-stream.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/www/x/json-motors-config.cgi \
		$(TARGET_DIR)/var/www/x/json-motors-config.cgi

	# Insert motors links into the web UI navigation at build time
	$(SED) 's|/\* THINGINO_MOTORS_NAV_ITEMS \*/|settingsItems.push({ label: "Pan/Tilt motors", href: "/config-motors.html" });|' \
		$(TARGET_DIR)/var/www/a/navigation.js

	# Enable motor controls on the preview page
	$(SED) 's|<!-- THINGINO_MOTORS_PREVIEW_SCRIPT -->|<script src="/a/preview-motors.js"></script>|' \
		$(TARGET_DIR)/var/www/preview.html

	# Re-apply cache-busting asset tags so motors pages are covered
	@asset_tag="$$(LC_ALL=C find $(THINGINO_MOTORS_PKGDIR)/files/www/a $(THINGINO_WEBUI_PKGDIR)/files/www/a \
		-type f \( -name '*.js' -o -name '*.css' \) -printf '%T@\n' 2>/dev/null | sort -nr | head -n1 | cut -d. -f1)"; \
	[ -n "$$asset_tag" ] || asset_tag="$$(date +%s)"; \
	python3 "$(THINGINO_WEBUI_PKGDIR)/scripts/apply_asset_tag.py" "$$asset_tag" "$(TARGET_DIR)/var/www"

	# Re-apply CDN fallbacks when local vendor files are present
	@vendor_src="$(THINGINO_WEBUI_PKGDIR)/files/www/a/vendor"; \
	if [ -d "$$vendor_src" ] && \
		[ -n "$$(find "$$vendor_src" -maxdepth 2 -type f ! -name '*.md' ! -name '.gitkeep' 2>/dev/null | head -1)" ]; then \
		python3 "$(THINGINO_WEBUI_PKGDIR)/scripts/apply_cdn_fallback.py" "$(TARGET_DIR)/var/www"; \
	fi
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

	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets.conf \
		$(TARGET_DIR)/etc/ptz_presets.conf

	$(THINGINO_MOTORS_INSTALL_JSON_CMDS)

	$(THINGINO_MOTORS_INSTALL_WWW_CMDS)
endef
endif

$(eval $(generic-package))
