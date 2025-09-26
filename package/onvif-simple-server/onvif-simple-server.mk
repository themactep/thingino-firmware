ONVIF_SIMPLE_SERVER_SITE_METHOD = git
ONVIF_SIMPLE_SERVER_SITE = https://github.com/roleoroleo/onvif_simple_server
ONVIF_SIMPLE_SERVER_SITE_BRANCH = master
ONVIF_SIMPLE_SERVER_VERSION = 2bb20a3e182d7898f385b2745189a35c6d0bfe49

ONVIF_SIMPLE_SERVER_LICENSE = MIT
ONVIF_SIMPLE_SERVER_LICENSE_FILES = LICENSE

ifeq ($(BR2_PACKAGE_MBEDTLS),y)
ONVIF_SIMPLE_SERVER_DEPENDENCIES += mbedtls cjson
MAKE_OPTS += HAVE_MBEDTLS=y
else ifeq ($(BR2_PACKAGE_THINGINO_WOLFSSL),y)
ONVIF_SIMPLE_SERVER_DEPENDENCIES += thingino-wolfssl cjson
MAKE_OPTS += HAVE_WOLFSSL=y
else
ONVIF_SIMPLE_SERVER_DEPENDENCIES += libtomcrypt
endif

ifeq ($(BR2_PACKAGE_ONVIF_SIMPLE_SERVER_ZLIB),y)
ONVIF_SIMPLE_SERVER_DEPENDENCIES += zlib
MAKE_OPTS += USE_ZLIB=y
endif

# username | uid | group | gid | password | home | shell | groups | comment
define ONVIF_SIMPLE_SERVER_USERS
thingino -1 thingino -1 =thingino - - - Streaming Service
endef

define ONVIF_SIMPLE_SERVER_BUILD_CMDS
	$(TARGET_CONFIGURE_OPTS) $(MAKE) LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D) $(MAKE_OPTS)
endef

define ONVIF_SIMPLE_SERVER_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/device_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/device_service_files \
		$(@D)/device_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/events_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/events_service_files \
		$(@D)/events_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/generic_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/generic_files \
		$(@D)/generic_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/media_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/media_service_files \
		$(@D)/media_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/media2_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/media2_service_files \
		$(@D)/media2_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/notify_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/notify_files \
		$(@D)/notify_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/ptz_service_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/ptz_service_files \
		$(@D)/ptz_service_files/*

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/onvif/wsd_files
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/var/www/onvif/wsd_files \
		$(@D)/wsd_files/*

	ln -sf /usr/sbin/onvif_simple_server $(TARGET_DIR)/var/www/onvif/device_service
	ln -sf /usr/sbin/onvif_simple_server $(TARGET_DIR)/var/www/onvif/events_service
	ln -sf /usr/sbin/onvif_simple_server $(TARGET_DIR)/var/www/onvif/media_service
	ln -sf /usr/sbin/onvif_simple_server $(TARGET_DIR)/var/www/onvif/media2_service
	ln -sf /usr/sbin/onvif_simple_server $(TARGET_DIR)/var/www/onvif/ptz_service

	$(INSTALL) -D -m 0755 $(@D)/onvif_notify_server \
		$(TARGET_DIR)/usr/sbin/onvif_notify_server

	$(INSTALL) -D -m 0755 $(@D)/onvif_simple_server \
		$(TARGET_DIR)/usr/sbin/onvif_simple_server

	$(INSTALL) -D -m 0755 $(@D)/wsd_simple_server \
		$(TARGET_DIR)/usr/sbin/wsd_simple_server

	$(INSTALL) -D -m 0644 $(ONVIF_SIMPLE_SERVER_PKGDIR)/files/onvif.conf \
		$(TARGET_DIR)/etc/onvif.conf

	$(INSTALL) -D -m 0755 $(ONVIF_SIMPLE_SERVER_PKGDIR)/files/S96onvif_discovery \
		$(TARGET_DIR)/etc/init.d/S96onvif_discovery

	$(INSTALL) -D -m 0755 $(ONVIF_SIMPLE_SERVER_PKGDIR)/files/S97onvif_notify \
		$(TARGET_DIR)/etc/init.d/S97onvif_notify
endef

$(eval $(generic-package))
