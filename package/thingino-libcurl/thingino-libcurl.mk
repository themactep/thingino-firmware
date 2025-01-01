THINGINO_LIBCURL_VERSION = 8.11.0
THINGINO_LIBCURL_SOURCE = curl-$(THINGINO_LIBCURL_VERSION).tar.xz
THINGINO_LIBCURL_SITE = https://curl.se/download
THINGINO_LIBCURL_DEPENDENCIES = host-pkgconf \
	$(if $(BR2_PACKAGE_ZLIB),zlib) \
	$(if $(BR2_PACKAGE_RTMPDUMP),rtmpdump)
THINGINO_LIBCURL_LICENSE = curl
THINGINO_LIBCURL_LICENSE_FILES = COPYING
THINGINO_LIBCURL_CPE_ID_VENDOR = haxx
THINGINO_LIBCURL_INSTALL_STAGING = YES

# We disable NTLM delegation to winbinds ntlm_auth ('--disable-ntlm-wb')
# support because it uses fork(), which doesn't work on non-MMU platforms.
# Moreover, this authentication method is probably almost never used (see
# https://curl.se/docs/manpage.html#--ntlm), so disable NTLM support overall.
#
# Likewise, there is no compiler on the target, so libcurl-option (to
# generate C code) isn't very useful
THINGINO_LIBCURL_CONF_OPTS = \
	--disable-manual \
	--disable-ntlm \
	--disable-ntlm-wb \
	--with-random=/dev/urandom \
	--disable-curldebug \
	--disable-libcurl-option

# Only affects Nest products.
# https://nvd.nist.gov/vuln/detail/CVE-2024-32928
THINGINO_LIBCURL_IGNORE_CVES += CVE-2024-32928

ifeq ($(BR2_TOOLCHAIN_HAS_THREADS),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-threaded-resolver
else
THINGINO_LIBCURL_CONF_OPTS += --disable-threaded-resolver
endif

ifeq ($(BR2_TOOLCHAIN_HAS_LIBATOMIC),y)
THINGINO_LIBCURL_CONF_OPTS += LIBS=-latomic
endif

ifeq ($(BR2_TOOLCHAIN_HAS_SYNC_1),)
# Even though stdatomic.h does exist, link fails for __atomic_exchange_1
# Work around this by pretending atomics aren't available.
THINGINO_LIBCURL_CONF_ENV += ac_cv_header_stdatomic_h=no
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_VERBOSE),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-verbose
else
THINGINO_LIBCURL_CONF_OPTS += --disable-verbose
endif

THINGINO_LIBCURL_CONFIG_SCRIPTS = curl-config

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_TLS_NONE),y)
THINGINO_LIBCURL_CONF_OPTS += --without-ssl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_OPENSSL),y)
THINGINO_LIBCURL_DEPENDENCIES += openssl
THINGINO_LIBCURL_CONF_OPTS += --with-openssl=$(STAGING_DIR)/usr \
	--with-ca-path=/etc/ssl/certs
else
THINGINO_LIBCURL_CONF_OPTS += --without-openssl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_BEARSSL),y)
THINGINO_LIBCURL_CONF_OPTS += --with-bearssl=$(STAGING_DIR)/usr
THINGINO_LIBCURL_DEPENDENCIES += bearssl
else
THINGINO_LIBCURL_CONF_OPTS += --without-bearssl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_GNUTLS),y)
THINGINO_LIBCURL_CONF_OPTS += --with-gnutls=$(STAGING_DIR)/usr \
	--with-ca-fallback
THINGINO_LIBCURL_DEPENDENCIES += gnutls
else
THINGINO_LIBCURL_CONF_OPTS += --without-gnutls
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_MBEDTLS),y)
THINGINO_LIBCURL_CONF_OPTS += --with-mbedtls=$(STAGING_DIR)/usr
THINGINO_LIBCURL_CONF_OPTS += --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
THINGINO_LIBCURL_DEPENDENCIES += mbedtls
else
THINGINO_LIBCURL_CONF_OPTS += --without-mbedtls
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_WOLFSSL),y)
THINGINO_LIBCURL_CONF_OPTS += --with-wolfssl=$(STAGING_DIR)/usr
THINGINO_LIBCURL_CONF_OPTS += --with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
THINGINO_LIBCURL_DEPENDENCIES += thingino-wolfssl
else
THINGINO_LIBCURL_CONF_OPTS += --without-wolfssl
endif

ifeq ($(BR2_PACKAGE_C_ARES),y)
THINGINO_LIBCURL_DEPENDENCIES += c-ares
THINGINO_LIBCURL_CONF_OPTS += --enable-ares
else
THINGINO_LIBCURL_CONF_OPTS += --disable-ares
endif

ifeq ($(BR2_PACKAGE_LIBIDN2),y)
THINGINO_LIBCURL_DEPENDENCIES += libidn2
THINGINO_LIBCURL_CONF_OPTS += --with-libidn2
else
THINGINO_LIBCURL_CONF_OPTS += --without-libidn2
endif

ifeq ($(BR2_PACKAGE_LIBPSL),y)
THINGINO_LIBCURL_DEPENDENCIES += libpsl
THINGINO_LIBCURL_CONF_OPTS += --with-libpsl
else
THINGINO_LIBCURL_CONF_OPTS += --without-libpsl
endif

# Configure curl to support libssh2
ifeq ($(BR2_PACKAGE_LIBSSH2),y)
THINGINO_LIBCURL_DEPENDENCIES += libssh2
THINGINO_LIBCURL_CONF_OPTS += --with-libssh2
else
THINGINO_LIBCURL_CONF_OPTS += --without-libssh2
endif

ifeq ($(BR2_PACKAGE_BROTLI),y)
THINGINO_LIBCURL_DEPENDENCIES += brotli
THINGINO_LIBCURL_CONF_OPTS += --with-brotli
else
THINGINO_LIBCURL_CONF_OPTS += --without-brotli
endif

ifeq ($(BR2_PACKAGE_NGHTTP2),y)
THINGINO_LIBCURL_DEPENDENCIES += nghttp2
THINGINO_LIBCURL_CONF_OPTS += --with-nghttp2
else
THINGINO_LIBCURL_CONF_OPTS += --without-nghttp2
endif

ifeq ($(BR2_PACKAGE_LIBGSASL),y)
THINGINO_LIBCURL_DEPENDENCIES += libgsasl
THINGINO_LIBCURL_CONF_OPTS += --with-libgsasl
else
THINGINO_LIBCURL_CONF_OPTS += --without-libgsasl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_COOKIES_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-cookies
else
THINGINO_LIBCURL_CONF_OPTS += --disable-cookies
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_PROXY_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-proxy
else
THINGINO_LIBCURL_CONF_OPTS += --disable-proxy
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_WEBSOCKETS_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-websockets
else
THINGINO_LIBCURL_CONF_OPTS += --disable-websockets
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_DICT_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-dict
else
THINGINO_LIBCURL_CONF_OPTS += --disable-dict
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_GOPHER_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-gopher
else
THINGINO_LIBCURL_CONF_OPTS += --disable-gopher
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_IMAP_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-imap
else
THINGINO_LIBCURL_CONF_OPTS += --disable-imap
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_LDAP_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-ldap
else
THINGINO_LIBCURL_CONF_OPTS += --disable-ldap
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_LDAPS_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-ldaps
else
THINGINO_LIBCURL_CONF_OPTS += --disable-ldaps
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_POP3_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-pop3
else
THINGINO_LIBCURL_CONF_OPTS += --disable-pop3
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_RTSP_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-rtsp
else
THINGINO_LIBCURL_CONF_OPTS += --disable-rtsp
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_SMB_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-smb
else
THINGINO_LIBCURL_CONF_OPTS += --disable-smb
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_SMTP_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-smtp
else
THINGINO_LIBCURL_CONF_OPTS += --disable-smtp
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_TELNET_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-telnet
else
THINGINO_LIBCURL_CONF_OPTS += --disable-telnet
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_TFTP_SUPPORT),y)
THINGINO_LIBCURL_CONF_OPTS += --enable-tftp
else
THINGINO_LIBCURL_CONF_OPTS += --disable-tftp
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_CURL),)
define THINGINO_LIBCURL_TARGET_CLEANUP
	rm -rf $(TARGET_DIR)/usr/bin/curl
endef
THINGINO_LIBCURL_POST_INSTALL_TARGET_HOOKS += THINGINO_LIBCURL_TARGET_CLEANUP
endif

$(eval $(autotools-package))
