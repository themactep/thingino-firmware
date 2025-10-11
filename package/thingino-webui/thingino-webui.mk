THINGINO_WEBUI_SITE_METHOD = local
THINGINO_WEBUI_SITE = $(THINGINO_WEBUI_PKGDIR)/files
THINGINO_WEBUI_LICENSE = MIT

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
	else \
		$(INSTALL) -D -m 0644 $(THINGINO_WEBUI_PKGDIR)/files/httpd.conf \
			$(TARGET_DIR)/etc/httpd.conf; \
		$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_PKGDIR)/files/S50httpd \
			$(TARGET_DIR)/etc/init.d/S50httpd; \
	fi

	$(INSTALL) -D -m 0755 $(@D)/mjpeg_frame \
		$(TARGET_DIR)/usr/bin/mjpeg_frame

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var
	cp -rv $(THINGINO_WEBUI_PKGDIR)/files/www $(TARGET_DIR)/var/

	$(INSTALL) -D -m 0755 $(@D)/mjpeg_inotify \
		$(TARGET_DIR)/var/www/x/mjpeg.cgi
endef

$(eval $(generic-package))
