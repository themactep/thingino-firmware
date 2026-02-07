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

define THINGINO_WEBUI_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=c99 -pedantic \
		-o $(@D)/mjpeg_frame $(@D)/mjpeg_frame.c
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=c99 -pedantic \
		-o $(@D)/mjpeg_inotify $(@D)/mjpeg_inotify.c
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

	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/S99heartbeat \
		$(TARGET_DIR)/etc/init.d/S99heartbeat

	# HTML pages
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/401.html \
		$(TARGET_DIR)/var/www/401.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-admin.html \
		$(TARGET_DIR)/var/www/config-admin.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-audio.html \
		$(TARGET_DIR)/var/www/config-audio.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-gpio.html \
		$(TARGET_DIR)/var/www/config-gpio.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-motors.html \
		$(TARGET_DIR)/var/www/config-motors.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-network.html \
		$(TARGET_DIR)/var/www/config-network.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-photosensing.html \
		$(TARGET_DIR)/var/www/config-photosensing.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-privacy.html \
		$(TARGET_DIR)/var/www/config-privacy.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-rtsp.html \
		$(TARGET_DIR)/var/www/config-rtsp.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-syslog.html \
		$(TARGET_DIR)/var/www/config-syslog.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-telegrambot.html \
		$(TARGET_DIR)/var/www/config-telegrambot.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-time.html \
		$(TARGET_DIR)/var/www/config-time.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-webui.html \
		$(TARGET_DIR)/var/www/config-webui.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-wireguard.html \
		$(TARGET_DIR)/var/www/config-wireguard.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/config-zerotier.html \
		$(TARGET_DIR)/var/www/config-zerotier.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/firmware-reset.html \
		$(TARGET_DIR)/var/www/config-reset.html
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
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/preview.html \
		$(TARGET_DIR)/var/www/preview.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/reset.html \
		$(TARGET_DIR)/var/www/reset.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/streamer-image.html \
		$(TARGET_DIR)/var/www/streamer-image.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/streamer-main.html \
		$(TARGET_DIR)/var/www/streamer-main.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/streamer-osd0.html \
		$(TARGET_DIR)/var/www/streamer-osd0.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/streamer-osd1.html \
		$(TARGET_DIR)/var/www/streamer-osd1.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/streamer-sensor.html \
		$(TARGET_DIR)/var/www/streamer-sensor.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/streamer-substream.html \
		$(TARGET_DIR)/var/www/streamer-substream.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-file-manager.html \
		$(TARGET_DIR)/var/www/tool-file-manager.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-ping-trace.html \
		$(TARGET_DIR)/var/www/tool-ping-trace.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-record.html \
		$(TARGET_DIR)/var/www/tool-record.html
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
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-sensor-data.html \
		$(TARGET_DIR)/var/www/tool-sensor-data.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-timelapse.html \
		$(TARGET_DIR)/var/www/tool-timelapse.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/tool-upgrade.html \
		$(TARGET_DIR)/var/www/tool-upgrade.html
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/wait.html \
		$(TARGET_DIR)/var/www/wait.html

	# JavaScripts
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/audio.js \
		$(TARGET_DIR)/var/www/a/audio.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-admin.js \
		$(TARGET_DIR)/var/www/a/config-admin.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-gpio.js \
		$(TARGET_DIR)/var/www/a/config-gpio.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-motors.js \
		$(TARGET_DIR)/var/www/a/config-motors.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-network.js \
		$(TARGET_DIR)/var/www/a/config-network.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-photosensing.js \
		$(TARGET_DIR)/var/www/a/config-photosensing.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-rtsp.js \
		$(TARGET_DIR)/var/www/a/config-rtsp.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-syslog.js \
		$(TARGET_DIR)/var/www/a/config-syslog.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-telegrambot.js \
		$(TARGET_DIR)/var/www/a/config-telegrambot.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-time.js \
		$(TARGET_DIR)/var/www/a/config-time.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-webui.js \
		$(TARGET_DIR)/var/www/a/config-webui.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-wireguard.js \
		$(TARGET_DIR)/var/www/a/config-wireguard.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/config-zerotier.js \
		$(TARGET_DIR)/var/www/a/config-zerotier.js
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
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/preview-motors.js \
		$(TARGET_DIR)/var/www/a/preview-motors.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/privacy.js \
		$(TARGET_DIR)/var/www/a/privacy.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/reset.js \
		$(TARGET_DIR)/var/www/a/reset.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/runtime-config.js \
		$(TARGET_DIR)/var/www/a/runtime-config.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/streamer-config.js \
		$(TARGET_DIR)/var/www/a/streamer-config.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/theme-init.js \
		$(TARGET_DIR)/var/www/a/theme-init.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-file-manager.js \
		$(TARGET_DIR)/var/www/a/tool-file-manager.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-ping-trace.js \
		$(TARGET_DIR)/var/www/a/tool-ping-trace.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-record.js \
		$(TARGET_DIR)/var/www/a/tool-record.js
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
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-sensor-data.js \
		$(TARGET_DIR)/var/www/a/tool-sensor-data.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-timelapse.js \
		$(TARGET_DIR)/var/www/a/tool-timelapse.js
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/tool-upgrade.js \
		$(TARGET_DIR)/var/www/a/tool-upgrade.js
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
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/wireguard.svg \
		$(TARGET_DIR)/var/www/a/wireguard.svg
	$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/www/a/zerotier.svg \
		$(TARGET_DIR)/var/www/a/zerotier.svg

	# CGI Scripts
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/api-key.cgi \
		$(TARGET_DIR)/var/www/x/api-key.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/auth.sh \
		$(TARGET_DIR)/var/www/x/auth.sh
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/ch0.jpg \
		$(TARGET_DIR)/var/www/x/ch0.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/ch0.mjpg \
		$(TARGET_DIR)/var/www/x/ch0.mjpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/ch1.jpg \
		$(TARGET_DIR)/var/www/x/ch1.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/ch1.mjpg \
		$(TARGET_DIR)/var/www/x/ch1.mjpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/ctl-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/ctl-telegrambot.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/dl0.jpg \
		$(TARGET_DIR)/var/www/x/dl0.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/dl1.jpg \
		$(TARGET_DIR)/var/www/x/dl1.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/dl2.cgi \
		$(TARGET_DIR)/var/www/x/dl2.jpg
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/events.cgi \
		$(TARGET_DIR)/var/www/x/events.cgi
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
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-gpio.cgi \
		$(TARGET_DIR)/var/www/x/json-config-gpio.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-network.cgi \
		$(TARGET_DIR)/var/www/x/json-config-network.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-rtsp.cgi \
		$(TARGET_DIR)/var/www/x/json-config-rtsp.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-send2.cgi \
		$(TARGET_DIR)/var/www/x/json-config-send2.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-syslog.cgi \
		$(TARGET_DIR)/var/www/x/json-config-syslog.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-time.cgi \
		$(TARGET_DIR)/var/www/x/json-config-time.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-webui.cgi \
		$(TARGET_DIR)/var/www/x/json-config-webui.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-wireguard.cgi \
		$(TARGET_DIR)/var/www/x/json-config-wireguard.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-config-zerotier.cgi \
		$(TARGET_DIR)/var/www/x/json-config-zerotier.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-gphotos-token.cgi \
		$(TARGET_DIR)/var/www/x/json-gphotos-token.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-gpio.cgi \
		$(TARGET_DIR)/var/www/x/json-gpio.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-heartbeat.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-heartbeat-lite.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat-lite.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-heartbeat-optimized.cgi \
		$(TARGET_DIR)/var/www/x/json-heartbeat-optimized.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-imaging.cgi \
		$(TARGET_DIR)/var/www/x/json-imaging.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-imp.cgi \
		$(TARGET_DIR)/var/www/x/json-imp.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-motion.cgi \
		$(TARGET_DIR)/var/www/x/json-motion.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-motor.cgi \
		$(TARGET_DIR)/var/www/x/json-motor.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-motor-params.cgi \
		$(TARGET_DIR)/var/www/x/json-motor-params.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-motors-config.cgi \
		$(TARGET_DIR)/var/www/x/json-motors-config.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-motor-stream.cgi \
		$(TARGET_DIR)/var/www/x/json-motor-stream.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-prudynt.cgi \
		$(TARGET_DIR)/var/www/x/json-prudynt.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-prudynt-config.cgi \
		$(TARGET_DIR)/var/www/x/json-prudynt-config.cgi
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
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-telegrambot.cgi \
		$(TARGET_DIR)/var/www/x/json-telegrambot.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-timegraph-stream.cgi \
		$(TARGET_DIR)/var/www/x/json-timegraph-stream.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/json-wireguard.cgi \
		$(TARGET_DIR)/var/www/x/json-wireguard.cgi
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
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/restart-prudynt.cgi \
		$(TARGET_DIR)/var/www/x/restart-prudynt.cgi
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
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-record.cgi \
		$(TARGET_DIR)/var/www/x/tool-record.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-sdcard.cgi \
		$(TARGET_DIR)/var/www/x/tool-sdcard.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/tool-upgrade.cgi \
		$(TARGET_DIR)/var/www/x/tool-upgrade.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/wifi-scan.cgi \
		$(TARGET_DIR)/var/www/x/wifi-scan.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/www/x/video.mjpg $(TARGET_DIR)/var/www/x/video.mjpg

	$(INSTALL) -D -m 0755 $(@D)/mjpeg_inotify \
		$(TARGET_DIR)/var/www/x/mjpeg.cgi

	$(INSTALL) -D -m 0755 $(@D)/mjpeg_frame \
		$(TARGET_DIR)/usr/bin/mjpeg_frame

	$(call THINGINO_WEBUI_APPLY_ASSET_TAG)
endef

$(eval $(generic-package))
