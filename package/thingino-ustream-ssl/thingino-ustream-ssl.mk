################################################################################
#
# thingino-ustream-ssl
#
################################################################################

THINGINO_USTREAM_SSL_VERSION = cea28c5bc43ae80c3531c98f4e4dc67b7dcf0ebb
THINGINO_USTREAM_SSL_SITE = https://git.openwrt.org/project/ustream-ssl.git
THINGINO_USTREAM_SSL_SITE_METHOD = git
THINGINO_USTREAM_SSL_LICENSE = ISC
THINGINO_USTREAM_SSL_LICENSE_FILES = ustream-ssl.h
THINGINO_USTREAM_SSL_INSTALL_STAGING = YES
THINGINO_USTREAM_SSL_DEPENDENCIES = thingino-libubox

ifeq ($(BR2_PACKAGE_MBEDTLS),y)
THINGINO_USTREAM_SSL_DEPENDENCIES += mbedtls
THINGINO_USTREAM_SSL_CONF_OPTS += -DMBEDTLS=ON
else
THINGINO_USTREAM_SSL_DEPENDENCIES += openssl
endif

$(eval $(cmake-package))
