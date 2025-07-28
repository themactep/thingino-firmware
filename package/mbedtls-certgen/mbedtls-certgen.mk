MBEDTLS_CERTGEN_VERSION = 1.0
MBEDTLS_CERTGEN_SITE_METHOD = local
MBEDTLS_CERTGEN_SITE = $(MBEDTLS_CERTGEN_PKGDIR)/files
MBEDTLS_CERTGEN_LICENSE = GPL-2.0+
MBEDTLS_CERTGEN_LICENSE_FILES = LICENSE

# Dependencies - support both standard and thingino mbedtls packages
ifeq ($(BR2_PACKAGE_MBEDTLS),y)
MBEDTLS_CERTGEN_DEPENDENCIES = mbedtls
MBEDTLS_CERTGEN_LIBS = -lmbedtls -lmbedx509 -lmbedcrypto
else ifeq ($(BR2_PACKAGE_THINGINO_MBEDTLS),y)
MBEDTLS_CERTGEN_DEPENDENCIES = thingino-mbedtls
MBEDTLS_CERTGEN_LIBS = -lmbedtls -lmbedx509 -lmbedcrypto
endif

define MBEDTLS_CERTGEN_BUILD_CMDS
	$(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS) -I$(STAGING_DIR)/usr/include" \
		LDFLAGS="$(TARGET_LDFLAGS) -L$(STAGING_DIR)/usr/lib" \
		LIBS="$(MBEDTLS_CERTGEN_LIBS)" \
		mbedtls-certgen
endef

define MBEDTLS_CERTGEN_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/mbedtls-certgen $(TARGET_DIR)/usr/bin/mbedtls-certgen-native
	$(INSTALL) -D -m 0755 $(@D)/mbedtls-certgen.sh $(TARGET_DIR)/usr/bin/mbedtls-certgen
endef

$(eval $(generic-package))
