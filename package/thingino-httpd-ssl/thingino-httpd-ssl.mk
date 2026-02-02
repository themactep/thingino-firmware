THINGINO_HTTPD_SSL_VERSION = 1.0.0
THINGINO_HTTPD_SSL_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-httpd-ssl/src
THINGINO_HTTPD_SSL_SITE_METHOD = local
THINGINO_HTTPD_SSL_LICENSE = GPL-2.0

# Support both standard and thingino mbedtls packages
ifeq ($(BR2_PACKAGE_MBEDTLS),y)
THINGINO_HTTPD_SSL_DEPENDENCIES = mbedtls mbedtls-certgen
else ifeq ($(BR2_PACKAGE_THINGINO_MBEDTLS),y)
THINGINO_HTTPD_SSL_DEPENDENCIES = thingino-mbedtls mbedtls-certgen
endif

define THINGINO_HTTPD_SSL_BUILD_CMDS
	$(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define THINGINO_HTTPD_SSL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/httpd-ssl \
		$(TARGET_DIR)/usr/sbin/httpd-ssl
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-httpd-ssl/files/S50httpd-ssl \
		$(TARGET_DIR)/etc/init.d/S50httpd-ssl
	mkdir -p $(TARGET_DIR)/etc/ssl/certs
	mkdir -p $(TARGET_DIR)/etc/ssl/private
endef

$(eval $(generic-package))

