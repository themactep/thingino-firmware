THINGINO_UHTTPD_VERSION = ebb92e6b339b88bbc6b76501b6603c52d4887ba1
THINGINO_UHTTPD_SITE = https://git.openwrt.org/project/uhttpd.git
THINGINO_UHTTPD_SITE_METHOD = git
THINGINO_UHTTPD_LICENSE = ISC
THINGINO_UHTTPD_LICENSE_FILES = uhttpd.h
THINGINO_UHTTPD_DEPENDENCIES = libubox json-c
THINGINO_UHTTPD_CONF_OPTS += -DCMAKE_BUILD_TYPE=Debug

ifeq ($(BR2_PACKAGE_LIBXCRYPT),y)
THINGINO_UHTTPD_DEPENDENCIES += libxcrypt
endif

# TLS support with different backends
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_TLS),y)
THINGINO_UHTTPD_CONF_OPTS += -DTLS_SUPPORT=ON

# mbedTLS backend
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS),y)
THINGINO_UHTTPD_DEPENDENCIES += ustream-ssl mbedtls
endif

# mbedTLS backend
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_TLS_OPENSSL),y)
THINGINO_UHTTPD_DEPENDENCIES += ustream-ssl openssl
endif

# wolfSSL backend
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_TLS_WOLFSSL),y)
THINGINO_UHTTPD_DEPENDENCIES += thingino-ustream-ssl thingino-wolfssl
endif

# Ensure at least one SSL backend is selected when TLS is enabled
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS)$(BR2_PACKAGE_THINGINO_UHTTPD_TLS_OPENSSL)$(BR2_PACKAGE_THINGINO_UHTTPD_TLS_WOLFSSL),)
$(warning TLS is enabled but no SSL backend is available. Disabling TLS support.)
THINGINO_UHTTPD_CONF_OPTS := $(filter-out -DTLS_SUPPORT=ON,$(THINGINO_UHTTPD_CONF_OPTS))
THINGINO_UHTTPD_CONF_OPTS += -DTLS_SUPPORT=OFF
endif

else
THINGINO_UHTTPD_CONF_OPTS += -DTLS_SUPPORT=OFF
endif

# ubus support
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_UBUS),y)
THINGINO_UHTTPD_DEPENDENCIES += ubus
THINGINO_UHTTPD_CONF_OPTS += -DUBUS_SUPPORT=ON
else
THINGINO_UHTTPD_CONF_OPTS += -DUBUS_SUPPORT=OFF
endif

# Lua support
ifeq ($(BR2_PACKAGE_THINGINO_UHTTPD_LUA),y)
THINGINO_UHTTPD_DEPENDENCIES += lua
THINGINO_UHTTPD_CONF_OPTS += -DLUA_SUPPORT=ON
else
THINGINO_UHTTPD_CONF_OPTS += -DLUA_SUPPORT=OFF
endif

# Thingino-specific configuration
THINGINO_UHTTPD_CONF_OPTS += \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_INSTALL_PREFIX=/usr

# Install basic web directory structure and certificate generation script
define THINGINO_UHTTPD_INSTALL_CONFIG
	# Create basic web directory structure
	mkdir -p $(TARGET_DIR)/var/www
	mkdir -p $(TARGET_DIR)/etc/ssl/certs $(TARGET_DIR)/etc/ssl/private
	# Note: Complete web interface provided by thingino-webui-lua package
endef

# Install certificate generation script (disabled - file missing)
# define THINGINO_UHTTPD_INSTALL_CERT_SCRIPT
#	$(INSTALL) -D -m 0755 $(THINGINO_UHTTPD_PKGDIR)/files/generate-ssl-cert \
#		$(TARGET_DIR)/usr/bin/generate-ssl-cert
# endef

THINGINO_UHTTPD_POST_INSTALL_TARGET_HOOKS += THINGINO_UHTTPD_INSTALL_CONFIG
# THINGINO_UHTTPD_POST_INSTALL_TARGET_HOOKS += THINGINO_UHTTPD_INSTALL_CERT_SCRIPT

# Note: uhttpd loads ustream-ssl dynamically via dlopen, no static linking needed

$(eval $(cmake-package))
