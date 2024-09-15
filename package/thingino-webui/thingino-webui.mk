THINGINO_WEBUI_SITE_METHOD = local
THINGINO_WEBUI_SITE = $(THINGINO_WEBUI_PKGDIR)/files
THINGINO_WEBUI_LICENSE = MIT
THINGINO_WEBUI_LICENSE_FILES = LICENSE

THINGINO_WEBUI_OVERRIDE_SRCDIR_RSYNC_EXCLUSIONS = \
	--exclude onvif/device_service \
        --exclude onvif/device_service_files \
        --exclude onvif/events_service \
        --exclude onvif/events_service_files \
        --exclude onvif/generic_files \
        --exclude onvif/media_service \
        --exclude onvif/media_service_files \
        --exclude onvif/notify_files \
        --exclude onvif/ptz_service \
        --exclude onvif/ptz_service_files \
        --exclude onvif/wsd_files \
	--exclude .idea

define THINGINO_WEBUI_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=c99 -pedantic -o $(@D)/mjpeg_frame $(@D)/mjpeg_frame.c
	$(TARGET_CC) $(TARGET_CFLAGS) $(TARGET_LDFLAGS) -std=c99 -pedantic -o $(@D)/mjpeg_inotify $(@D)/mjpeg_inotify.c
endef

define THINGINO_WEBUI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/etc $(THINGINO_WEBUI_PKGDIR)/files/etc/httpd.conf

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 0755 -t $(TARGET_DIR)/etc/init.d $(THINGINO_WEBUI_PKGDIR)/files/etc/init.d/S50httpd

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/bin $(@D)/mjpeg_frame

	if grep -q "^BR2_THINGINO_DEV_PACKAGES=y" $(BR2_CONFIG); then \
		$(INSTALL) -m 0755 -t $(TARGET_DIR)/etc/init.d $(THINGINO_WEBUI_PKGDIR)/files/etc/init.d/S44devmounts; \
	fi

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var
	cp -rv $(THINGINO_WEBUI_PKGDIR)/files/var/www $(TARGET_DIR)/var/
	find $(TARGET_DIR)/var/www/x/ -type f -name *.cgi -exec chmod 755 {} \;
	find $(TARGET_DIR)/var/www/a/ -type f ! -name "*.gz" -exec gzip -9 {} \;

	$(INSTALL) -m 0755 -T $(@D)/mjpeg_inotify $(TARGET_DIR)/var/www/x/mjpeg.cgi
endef

$(eval $(generic-package))
