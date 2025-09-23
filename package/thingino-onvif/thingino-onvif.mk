THINGINO_ONVIF_SITE_METHOD = git
THINGINO_ONVIF_SITE = https://github.com/themactep/thingino-onvif
THINGINO_ONVIF_SITE_BRANCH = master
THINGINO_ONVIF_VERSION = ff3f1e79851c4ca9e0fa43f5b3c9c9cf83ad809b

THINGINO_ONVIF_LICENSE = MIT
THINGINO_ONVIF_LICENSE_FILES = LICENSE

# uClibc compatibility for zlib off64_t issue
ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
define THINGINO_ONVIF_UCLIBC_FIX
	# Add off64_t typedef before including zlib.h
	for file in $(@D)/*.c; do \
		if grep -q '#include.*zlib.h' "$$file"; then \
			sed -i '/#include.*zlib.h/i #ifndef off64_t\n#define off64_t off_t\n#endif' "$$file"; \
		fi; \
	done
endef
THINGINO_ONVIF_PRE_BUILD_HOOKS += THINGINO_ONVIF_UCLIBC_FIX
endif

THINGINO_ONVIF_DEPENDENCIES += json-c

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
