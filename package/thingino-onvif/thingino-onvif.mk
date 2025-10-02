THINGINO_ONVIF_SITE_METHOD = git
THINGINO_ONVIF_SITE = https://github.com/themactep/thingino-onvif
THINGINO_ONVIF_SITE_BRANCH = master
THINGINO_ONVIF_VERSION = f8eac8b17dd3dd9efad5585c2091ecd843f70b34
#$(shell git ls-remote $(THINGINO_ONVIF_SITE) $(THINGINO_ONVIF_SITE_BRANCH) | head -1 | cut -f1)

THINGINO_ONVIF_LICENSE = MIT
THINGINO_ONVIF_LICENSE_FILES = LICENSE

THINGINO_ONVIF_DEPENDENCIES += thingino-jct thingino-mxml

ifeq ($(BR2_PACKAGE_MBEDTLS),y)
THINGINO_ONVIF_DEPENDENCIES += mbedtls
MAKE_OPTS += HAVE_MBEDTLS=y
else ifeq ($(BR2_PACKAGE_THINGINO_WOLFSSL),y)
THINGINO_ONVIF_DEPENDENCIES += thingino-wolfssl
MAKE_OPTS += HAVE_WOLFSSL=y
else
THINGINO_ONVIF_DEPENDENCIES += libtomcrypt
endif

# username | uid | group | gid | password | home | shell | groups | comment
define THINGINO_ONVIF_USERS
thingino -1 thingino -1 =thingino - - - Streaming Service
endef

define THINGINO_ONVIF_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) \
		CFLAGS="$(TARGET_CFLAGS) $(THINGINO_ONVIF_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D) $(MAKE_OPTS)
endef

define THINGINO_ONVIF_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/device_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/device_service_files \
		$(@D)/res/device_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/deviceio_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/deviceio_service_files \
		$(@D)/res/deviceio_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/events_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/events_service_files \
		$(@D)/res/events_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/generic_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/generic_files \
		$(@D)/res/generic_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/media_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/media_service_files \
		$(@D)/res/media_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/media2_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/media2_service_files \
		$(@D)/res/media2_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/notify_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/notify_files \
		$(@D)/res/notify_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/ptz_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/ptz_service_files \
		$(@D)/res/ptz_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/wsd_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/wsd_files \
		$(@D)/res/wsd_files/*

	$(INSTALL) -D -m 0755 $(@D)/onvif_simple_server \
		$(TARGET_DIR)/usr/sbin/onvif.cgi
	ln -sf /usr/sbin/onvif.cgi $(TARGET_DIR)/var/www/onvif/device_service
	ln -sf /usr/sbin/onvif.cgi $(TARGET_DIR)/var/www/onvif/deviceio_service
	ln -sf /usr/sbin/onvif.cgi $(TARGET_DIR)/var/www/onvif/events_service
	ln -sf /usr/sbin/onvif.cgi $(TARGET_DIR)/var/www/onvif/media_service
	ln -sf /usr/sbin/onvif.cgi $(TARGET_DIR)/var/www/onvif/media2_service
	ln -sf /usr/sbin/onvif.cgi $(TARGET_DIR)/var/www/onvif/ptz_service

	$(INSTALL) -D -m 0755 $(@D)/onvif_notify_server \
		$(TARGET_DIR)/usr/sbin/onvif_notify_server

	$(INSTALL) -D -m 0755 $(@D)/wsd_simple_server \
		$(TARGET_DIR)/usr/sbin/wsd_simple_server

	$(INSTALL) -D -m 0644 $(@D)/res/onvif.json \
		$(TARGET_DIR)/etc/onvif.json

	$(INSTALL) -D -m 0755 $(THINGINO_ONVIF_PKGDIR)/files/S96onvif_discovery \
		$(TARGET_DIR)/etc/init.d/S96onvif_discovery

	$(INSTALL) -D -m 0755 $(THINGINO_ONVIF_PKGDIR)/files/S97onvif_notify \
		$(TARGET_DIR)/etc/init.d/S97onvif_notify
endef

$(eval $(generic-package))
