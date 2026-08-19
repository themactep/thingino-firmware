THINGINO_WEBUI_SITE_METHOD = local
THINGINO_WEBUI_SITE = $(THINGINO_WEBUI_PKGDIR)/files
THINGINO_WEBUI_LICENSE = MIT

THINGINO_WEBUI_ASSET_TAG_RAW := $(shell LC_ALL=C find $(THINGINO_WEBUI_PKGDIR)/files/www/a -type f \( -name '*.js' -o -name '*.css' \) -printf '%T@\n' 2>/dev/null | sort -nr | head -n1 | cut -d. -f1)
THINGINO_WEBUI_ASSET_TAG := $(if $(THINGINO_WEBUI_ASSET_TAG_RAW),$(THINGINO_WEBUI_ASSET_TAG_RAW),$(shell date +%s))

define THINGINO_WEBUI_APPLY_ASSET_TAG
	@asset_tag="$(THINGINO_WEBUI_ASSET_TAG)"; \
	root="$(TARGET_DIR)/var/www"; \
	script="$(THINGINO_WEBUI_PKGDIR)/scripts/apply_asset_tag.py"; \
	if [ -z "$$asset_tag" ]; then \
		asset_tag="$$(date +%s)"; \
	fi; \
	if [ -d "$$root" ] && [ -f "$$script" ]; then \
		python3 "$$script" "$$asset_tag" "$$root"; \
	else \
		printf 'thingino-webui: asset tag injection skipped (missing %s or %s)\n' "$$root" "$$script"; \
	fi
endef

# HTML pages reference CDN assets by default.
# When BR2_PACKAGE_THINGINO_WEBUI_PARANOID=y, apply_paranoid_mode.py
# rewrites CDN <link>/<script> tags to local /a/vendor/ paths and
# vendor files are installed. The CDN fallback step below is a no-op
# when no CDN tags remain (paranoid mode) and adds onerror= fallbacks
# when they do (normal mode).
define THINGINO_WEBUI_APPLY_CDN_FALLBACK
	@root="$(TARGET_DIR)/var/www"; \
	script="$(THINGINO_WEBUI_PKGDIR)/scripts/apply_cdn_fallback.py"; \
	vendor_src="$(THINGINO_WEBUI_PKGDIR)/files/www/a/vendor"; \
	if [ -f "$$script" ] && [ -d "$$vendor_src" ] && \
		[ -n "$$(find "$$vendor_src" -maxdepth 2 -type f ! -name '*.md' ! -name '.gitkeep' 2>/dev/null | head -1)" ]; then \
		python3 "$$script" "$$root"; \
	else \
		printf 'thingino-webui: CDN fallback skipped (no vendor files in %s)\n' "$$vendor_src"; \
	fi
endef

define THINGINO_WEBUI_INSTALL_TARGET_CMDS
	if grep -q "^BR2_PACKAGE_NGINX=y" $(BR2_CONFIG); then \
		$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/nginx.conf \
			$(TARGET_DIR)/etc/nginx/nginx.conf; \
	elif grep -q "^BR2_PACKAGE_THINGINO_UHTTPD=y" $(BR2_CONFIG); then \
		: ; \
	elif grep -q "^BR2_PACKAGE_BUSYBOX_HTTPD=y" $(BR2_CONFIG); then \
		$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/httpd.conf \
			$(TARGET_DIR)/etc/httpd.conf; \
		$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/S90httpd \
			$(TARGET_DIR)/etc/init.d/S90httpd; \
	fi

	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/S48webui-config \
		$(TARGET_DIR)/etc/init.d/S48webui-config
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/S91mqttsub \
		$(TARGET_DIR)/etc/init.d/S91mqttsub
#	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/S99heartbeat \
#		$(TARGET_DIR)/etc/init.d/S99heartbeat

	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/mqtt-sub-dispatcher \
		$(TARGET_DIR)/usr/sbin/mqtt-sub-dispatcher
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/heartbeat-lib.sh \
		$(TARGET_DIR)/usr/libexec/thingino-webui/heartbeat-lib.sh

	# camera-only services
	if [ "$(BR2_THINGINO_DEV_IPCAM)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/telegram-cam-register \
			$(TARGET_DIR)/usr/sbin/telegram-cam-register; \
		$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/telegram-cam-agent \
			$(TARGET_DIR)/usr/sbin/telegram-cam-agent; \
	else \
		rm -f $(TARGET_DIR)/usr/sbin/telegram-cam-register \
			$(TARGET_DIR)/usr/sbin/telegram-cam-agent; \
	fi

	# HTML pages
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/401.html \
		$(TARGET_DIR)/var/www/401.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-admin.html \
		$(TARGET_DIR)/var/www/config-admin.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-network.html \
		$(TARGET_DIR)/var/www/config-network.html

	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-syslog.html \
		$(TARGET_DIR)/var/www/config-syslog.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-time.html \
		$(TARGET_DIR)/var/www/config-time.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-webui.html \
		$(TARGET_DIR)/var/www/config-webui.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/firmware-reset.html \
		$(TARGET_DIR)/var/www/firmware-reset.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/gphotos-auth-callback.html \
		$(TARGET_DIR)/var/www/gphotos-auth-callback.html
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/index.cgi \
		$(TARGET_DIR)/var/www/index.cgi
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/index.html \
		$(TARGET_DIR)/var/www/index.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/info.html \
		$(TARGET_DIR)/var/www/info.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/info-diagnostic.html \
		$(TARGET_DIR)/var/www/info-diagnostic.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/info-overlay.html \
		$(TARGET_DIR)/var/www/info-overlay.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/info-usage.html \
		$(TARGET_DIR)/var/www/info-usage.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/login.html \
		$(TARGET_DIR)/var/www/login.html
	# Core preview page. A streamer package that needs a different
	# implementation (raptor, timps) ships its own preview.html under the
	# same filename and installs it straight over this one from its own
	# INSTALL_TARGET_CMDS/POST_INSTALL_TARGET_HOOKS (with a dependency on
	# thingino-webui for ordering) - plain overwrite, before plugin
	# assembly below ever runs. prudynt-t installs none, so this stays.
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/preview.html \
		$(TARGET_DIR)/var/www/preview.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/reset.html \
		$(TARGET_DIR)/var/www/reset.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-file-manager.html \
		$(TARGET_DIR)/var/www/tool-file-manager.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-ping-trace.html \
		$(TARGET_DIR)/var/www/tool-ping-trace.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-sdcard.html \
		$(TARGET_DIR)/var/www/tool-sdcard.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2.html \
		$(TARGET_DIR)/var/www/tool-send2.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-email.html \
		$(TARGET_DIR)/var/www/tool-send2-email.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-ftp.html \
		$(TARGET_DIR)/var/www/tool-send2-ftp.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-gphotos.html \
		$(TARGET_DIR)/var/www/tool-send2-gphotos.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-gotify.html \
		$(TARGET_DIR)/var/www/tool-send2-gotify.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-mqtt.html \
		$(TARGET_DIR)/var/www/tool-send2-mqtt.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-ntfy.html \
		$(TARGET_DIR)/var/www/tool-send2-ntfy.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-storage.html \
		$(TARGET_DIR)/var/www/tool-send2-storage.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-telegram.html \
		$(TARGET_DIR)/var/www/tool-send2-telegram.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-webhook.html \
		$(TARGET_DIR)/var/www/tool-send2-webhook.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-send2-xmpp.html \
		$(TARGET_DIR)/var/www/tool-send2-xmpp.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-sensor-data.html \
		$(TARGET_DIR)/var/www/tool-sensor-data.html
	if [ "$(BR2_THINGINO_DEV_PACKAGES)" = "y" ]; then \
		$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-upgrade.html \
			$(TARGET_DIR)/var/www/tool-upgrade.html; \
	else \
		rm -f $(TARGET_DIR)/var/www/tool-upgrade.html; \
	fi
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/wait.html \
		$(TARGET_DIR)/var/www/wait.html

	# JavaScripts
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-admin.js \
		$(TARGET_DIR)/var/www/a/config-admin.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-network.js \
		$(TARGET_DIR)/var/www/a/config-network.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-syslog.js \
		$(TARGET_DIR)/var/www/a/config-syslog.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-time.js \
		$(TARGET_DIR)/var/www/a/config-time.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-webui.js \
		$(TARGET_DIR)/var/www/a/config-webui.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/control-bar.js \
		$(TARGET_DIR)/var/www/a/control-bar.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/firmware-reset.js \
		$(TARGET_DIR)/var/www/a/firmware-reset.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/footer.js \
		$(TARGET_DIR)/var/www/a/footer.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/gphotos-auth-callback.js \
		$(TARGET_DIR)/var/www/a/gphotos-auth-callback.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/info-diagnostic.js \
		$(TARGET_DIR)/var/www/a/info-diagnostic.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/info.js \
		$(TARGET_DIR)/var/www/a/info.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/info-overlay.js \
		$(TARGET_DIR)/var/www/a/info-overlay.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/info-usage.js \
		$(TARGET_DIR)/var/www/a/info-usage.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/main.js \
		$(TARGET_DIR)/var/www/a/main.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/navigation.js \
		$(TARGET_DIR)/var/www/a/navigation.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/preview.js \
		$(TARGET_DIR)/var/www/a/preview.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/sei-rotate.js \
		$(TARGET_DIR)/var/www/a/sei-rotate.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/reset.js \
		$(TARGET_DIR)/var/www/a/reset.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/theme-init.js \
		$(TARGET_DIR)/var/www/a/theme-init.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-file-manager.js \
		$(TARGET_DIR)/var/www/a/tool-file-manager.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-ping-trace.js \
		$(TARGET_DIR)/var/www/a/tool-ping-trace.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-sdcard.js \
		$(TARGET_DIR)/var/www/a/tool-sdcard.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2.js \
		$(TARGET_DIR)/var/www/a/tool-send2.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-email.js \
		$(TARGET_DIR)/var/www/a/tool-send2-email.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-ftp.js \
		$(TARGET_DIR)/var/www/a/tool-send2-ftp.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-gphotos.js \
		$(TARGET_DIR)/var/www/a/tool-send2-gphotos.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-gotify.js \
		$(TARGET_DIR)/var/www/a/tool-send2-gotify.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-mqtt.js \
		$(TARGET_DIR)/var/www/a/tool-send2-mqtt.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-ntfy.js \
		$(TARGET_DIR)/var/www/a/tool-send2-ntfy.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-storage.js \
		$(TARGET_DIR)/var/www/a/tool-send2-storage.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-telegram.js \
		$(TARGET_DIR)/var/www/a/tool-send2-telegram.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-webhook.js \
		$(TARGET_DIR)/var/www/a/tool-send2-webhook.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-send2-xmpp.js \
		$(TARGET_DIR)/var/www/a/tool-send2-xmpp.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-sensor-data.js \
		$(TARGET_DIR)/var/www/a/tool-sensor-data.js
	if [ "$(BR2_THINGINO_DEV_PACKAGES)" = "y" ]; then \
		$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-upgrade.js \
			$(TARGET_DIR)/var/www/a/tool-upgrade.js; \
	else \
		rm -f $(TARGET_DIR)/var/www/a/tool-upgrade.js; \
	fi
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/wait.js \
		$(TARGET_DIR)/var/www/a/wait.js

	[ -h "$(TARGET_DIR)/var/www/a/tz.json" ] || \
		ln -s /usr/share/tz.json $(TARGET_DIR)/var/www/a/tz.json

	# Styles
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/main.css \
		$(TARGET_DIR)/var/www/a/main.css

	# Images
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/logo.svg \
		$(TARGET_DIR)/var/www/a/logo.svg
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/favicon.svg \
		$(TARGET_DIR)/var/www/a/favicon.svg
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/nostream.svg \
		$(TARGET_DIR)/var/www/a/nostream.svg

	# CGI Scripts
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/api-key.cgi \
		$(TARGET_DIR)/var/www/x/api-key.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/agent.cgi \
		$(TARGET_DIR)/var/www/x/agent.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/auth.sh \
		$(TARGET_DIR)/var/www/x/auth.sh
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/dl2.cgi \
		$(TARGET_DIR)/var/www/x/dl2.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/firmware-reset.cgi \
		$(TARGET_DIR)/var/www/x/firmware-reset.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/image.raw \
		$(TARGET_DIR)/var/www/x/image.raw
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/info.cgi \
		$(TARGET_DIR)/var/www/x/info.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/info-diagnostic.cgi \
		$(TARGET_DIR)/var/www/x/info-diagnostic.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/info-overlay.cgi \
		$(TARGET_DIR)/var/www/x/info-overlay.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-admin.cgi \
		$(TARGET_DIR)/var/www/x/json-config-admin.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-network.cgi \
		$(TARGET_DIR)/var/www/x/json-config-network.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-send2.cgi \
		$(TARGET_DIR)/var/www/x/json-config-send2.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-syslog.cgi \
		$(TARGET_DIR)/var/www/x/json-config-syslog.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-time.cgi \
		$(TARGET_DIR)/var/www/x/json-config-time.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-webui.cgi \
		$(TARGET_DIR)/var/www/x/json-config-webui.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-agent-token.cgi \
		$(TARGET_DIR)/var/www/x/json-agent-token.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-gphotos-token.cgi \
		$(TARGET_DIR)/var/www/x/json-gphotos-token.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-heartbeat.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-heartbeat-slow.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat-slow.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-imp.cgi \
		$(TARGET_DIR)/var/www/x/json-imp.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-reset-ntp.cgi \
		$(TARGET_DIR)/var/www/x/json-reset-ntp.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-send2.cgi \
		$(TARGET_DIR)/var/www/x/json-send2.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-sensor-info.cgi \
		$(TARGET_DIR)/var/www/x/json-sensor-info.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-sync-time.cgi \
		$(TARGET_DIR)/var/www/x/json-sync-time.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-system-usage.cgi \
		$(TARGET_DIR)/var/www/x/json-system-usage.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/legacy-url-recovery.cgi \
		$(TARGET_DIR)/var/www/x/legacy-url-recovery.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/login.cgi \
		$(TARGET_DIR)/var/www/x/login.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/logout.cgi \
		$(TARGET_DIR)/var/www/x/logout.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/reboot.cgi \
		$(TARGET_DIR)/var/www/x/reboot.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/reset.cgi \
		$(TARGET_DIR)/var/www/x/reset.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/restart-httpd.cgi \
		$(TARGET_DIR)/var/www/x/restart-httpd.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/restore.cgi \
		$(TARGET_DIR)/var/www/x/restore.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/run.cgi \
		$(TARGET_DIR)/var/www/x/run.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/send.cgi \
		$(TARGET_DIR)/var/www/x/send.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/session.sh \
		$(TARGET_DIR)/var/www/x/session.sh
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/session-status.cgi \
		$(TARGET_DIR)/var/www/x/session-status.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/texteditor.cgi \
		$(TARGET_DIR)/var/www/x/texteditor.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-file-manager.cgi \
		$(TARGET_DIR)/var/www/x/tool-file-manager.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-ping-trace.cgi \
		$(TARGET_DIR)/var/www/x/tool-ping-trace.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-sdcard.cgi \
		$(TARGET_DIR)/var/www/x/tool-sdcard.cgi
	if [ "$(BR2_THINGINO_DEV_PACKAGES)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-upgrade.cgi \
			$(TARGET_DIR)/var/www/x/tool-upgrade.cgi; \
	else \
		rm -f $(TARGET_DIR)/var/www/x/tool-upgrade.cgi; \
	fi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/wifi-scan.cgi \
		$(TARGET_DIR)/var/www/x/wifi-scan.cgi

	# Paranoid mode: install local vendor assets (CDN rewriting happens in
	# finalize hook so plugin pages installed later are also processed)
	@if grep -q "^BR2_PACKAGE_THINGINO_WEBUI_PARANOID=y" $(BR2_CONFIG); then \
		rm -rf "$(TARGET_DIR)/var/www/a/vendor"; \
		cp -r "$(THINGINO_WEBUI_PKGDIR)/files/www/a/vendor" "$(TARGET_DIR)/var/www/a/"; \
		printf 'thingino-webui: paranoid mode — vendor files staged\n'; \
	fi

	$(call THINGINO_WEBUI_APPLY_ASSET_TAG)
	$(call THINGINO_WEBUI_APPLY_CDN_FALLBACK)
endef

# Paranoid mode CDN → local rewriting — runs as a rootfs pre-hook (not a
# per-package finalize hook) so it runs AFTER the finalize hooks of streamer
# packages (timps, raptor) that install their own HTML overlays.  Plugin
# assembly (ASSEMBLE_PLUGINS) has also already run by this point.
define THINGINO_WEBUI_PARANOID_REWRITE
	if grep -q "^BR2_PACKAGE_THINGINO_WEBUI_PARANOID=y" $(BR2_CONFIG); then \
		python3 "$(THINGINO_WEBUI_PKGDIR)/scripts/apply_paranoid_mode.py" "$(TARGET_DIR)/var/www" || true; \
	fi
endef
ROOTFS_PRE_CMD_HOOKS += THINGINO_WEBUI_PARANOID_REWRITE

# Plugin assembly finalize hook — runs after every package is installed,
# discovers *.webui.json manifests, merges nav/scripts/styles, and re-applies
# asset tags and CDN fallbacks.
#
# Failures are fatal on purpose: every error assemble_plugins.py raises is a
# manifest conflict (duplicate plugin name, two plugins claiming the same page,
# two providers for the same extension point) that silently produces a broken
# WebUI. Swallowing them just moves the discovery to the camera.
define THINGINO_WEBUI_ASSEMBLE_PLUGINS
	@python3 "$(THINGINO_WEBUI_PKGDIR)/scripts/assemble_plugins.py" "$(TARGET_DIR)"
endef
THINGINO_WEBUI_TARGET_FINALIZE_HOOKS += THINGINO_WEBUI_ASSEMBLE_PLUGINS

$(eval $(generic-package))
