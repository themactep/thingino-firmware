################################################################################
#
# libcurl overrides for Thingino
#
################################################################################

# The override file is included before package/*.mk, so any 'override' variable
# set here takes ownership before libcurl.mk can assign it.  We therefore must
# set every configure option we care about here; libcurl.mk's assignments are
# ignored for variables we claim with 'override'.

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL),y)

# Only affects Google Nest products.
# https://nvd.nist.gov/vuln/detail/CVE-2024-32928
LIBCURL_IGNORE_CVES += CVE-2024-32928

# Base flags (mirrors libcurl.mk defaults, adds ntlm-wb and random source)
override LIBCURL_CONF_OPTS = \
	--disable-manual \
	--disable-ntlm \
	--disable-ntlm-wb \
	--with-random=/dev/urandom \
	--disable-curldebug \
	--disable-libcurl-option

# Toolchain-dependent options
ifeq ($(BR2_TOOLCHAIN_HAS_THREADS)x$(BR2_PACKAGE_C_ARES),yx)
override LIBCURL_CONF_OPTS += --enable-threaded-resolver
else
override LIBCURL_CONF_OPTS += --disable-threaded-resolver
endif

ifeq ($(BR2_TOOLCHAIN_HAS_LIBATOMIC),y)
override LIBCURL_CONF_OPTS += LIBS=-latomic
endif

ifeq ($(BR2_TOOLCHAIN_HAS_SYNC_1),)
override LIBCURL_CONF_ENV += ac_cv_header_stdatomic_h=no
endif

# Verbose
ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_VERBOSE),y)
override LIBCURL_CONF_OPTS += --enable-verbose
else
override LIBCURL_CONF_OPTS += --disable-verbose
endif

override LIBCURL_CONFIG_SCRIPTS = curl-config

# Base dependencies (mirrors libcurl.mk)
override LIBCURL_DEPENDENCIES = host-pkgconf \
	$(if $(BR2_PACKAGE_ZLIB),zlib) \
	$(if $(BR2_PACKAGE_THINGINO_LIBCURL_RTMP_SUPPORT),rtmpdump)

# TLS backends
ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_TLS_NONE),y)
override LIBCURL_CONF_OPTS += --without-ssl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_OPENSSL),y)
override LIBCURL_DEPENDENCIES += openssl
override LIBCURL_CONF_OPTS += \
	--with-openssl=$(STAGING_DIR)/usr \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
else
override LIBCURL_CONF_OPTS += --without-openssl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_GNUTLS),y)
override LIBCURL_CONF_OPTS += \
	--with-gnutls=$(STAGING_DIR)/usr \
	--with-ca-fallback
override LIBCURL_DEPENDENCIES += gnutls
else
override LIBCURL_CONF_OPTS += --without-gnutls
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_MBEDTLS),y)
override LIBCURL_CONF_OPTS += \
	--with-mbedtls=$(STAGING_DIR)/usr \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
override LIBCURL_DEPENDENCIES += mbedtls
else
override LIBCURL_CONF_OPTS += --without-mbedtls
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_WOLFSSL),y)
override LIBCURL_CONF_OPTS += \
	--with-wolfssl=$(STAGING_DIR)/usr \
	--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt
override LIBCURL_DEPENDENCIES += wolfssl
else
override LIBCURL_CONF_OPTS += --without-wolfssl
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_BEARSSL),y)
override LIBCURL_CONF_OPTS += --with-bearssl=$(STAGING_DIR)/usr
override LIBCURL_DEPENDENCIES += bearssl
else
override LIBCURL_CONF_OPTS += --without-bearssl
endif

# Optional library integrations (delegated to Buildroot's own detection)
ifeq ($(BR2_PACKAGE_C_ARES),y)
override LIBCURL_DEPENDENCIES += c-ares
override LIBCURL_CONF_OPTS += --enable-ares
else
override LIBCURL_CONF_OPTS += --disable-ares
endif

ifeq ($(BR2_PACKAGE_LIBIDN2),y)
override LIBCURL_DEPENDENCIES += libidn2
override LIBCURL_CONF_OPTS += --with-libidn2
else
override LIBCURL_CONF_OPTS += --without-libidn2
endif

ifeq ($(BR2_PACKAGE_LIBPSL),y)
override LIBCURL_DEPENDENCIES += libpsl
override LIBCURL_CONF_OPTS += --with-libpsl
else
override LIBCURL_CONF_OPTS += --without-libpsl
endif

ifeq ($(BR2_PACKAGE_LIBSSH2),y)
override LIBCURL_DEPENDENCIES += libssh2
override LIBCURL_CONF_OPTS += --with-libssh2
else
override LIBCURL_CONF_OPTS += --without-libssh2
endif

ifeq ($(BR2_PACKAGE_BROTLI),y)
override LIBCURL_DEPENDENCIES += brotli
override LIBCURL_CONF_OPTS += --with-brotli
else
override LIBCURL_CONF_OPTS += --without-brotli
endif

ifeq ($(BR2_PACKAGE_NGHTTP2),y)
override LIBCURL_DEPENDENCIES += nghttp2
override LIBCURL_CONF_OPTS += --with-nghttp2
else
override LIBCURL_CONF_OPTS += --without-nghttp2
endif

ifeq ($(BR2_PACKAGE_LIBGSASL),y)
override LIBCURL_DEPENDENCIES += libgsasl
override LIBCURL_CONF_OPTS += --with-libgsasl
else
override LIBCURL_CONF_OPTS += --without-libgsasl
endif

# Per-protocol feature flags
ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_COOKIES_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-cookies
else
override LIBCURL_CONF_OPTS += --disable-cookies
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_PROXY_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-proxy
else
override LIBCURL_CONF_OPTS += --disable-proxy
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_WEBSOCKETS_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-websockets
else
override LIBCURL_CONF_OPTS += --disable-websockets
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_MQTT_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-mqtt
else
override LIBCURL_CONF_OPTS += --disable-mqtt
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_DICT_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-dict
else
override LIBCURL_CONF_OPTS += --disable-dict
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_GOPHER_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-gopher
else
override LIBCURL_CONF_OPTS += --disable-gopher
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_IMAP_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-imap
else
override LIBCURL_CONF_OPTS += --disable-imap
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_LDAP_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-ldap
else
override LIBCURL_CONF_OPTS += --disable-ldap
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_LDAPS_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-ldaps
else
override LIBCURL_CONF_OPTS += --disable-ldaps
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_POP3_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-pop3
else
override LIBCURL_CONF_OPTS += --disable-pop3
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_RTSP_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-rtsp
else
override LIBCURL_CONF_OPTS += --disable-rtsp
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_SMB_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-smb
else
override LIBCURL_CONF_OPTS += --disable-smb
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_SMTP_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-smtp
else
override LIBCURL_CONF_OPTS += --disable-smtp
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_TELNET_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-telnet
else
override LIBCURL_CONF_OPTS += --disable-telnet
endif

ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_TFTP_SUPPORT),y)
override LIBCURL_CONF_OPTS += --enable-tftp
else
override LIBCURL_CONF_OPTS += --disable-tftp
endif

# curl binary
ifeq ($(BR2_PACKAGE_THINGINO_LIBCURL_CURL),)
override define LIBCURL_TARGET_CLEANUP
	rm -rf $(TARGET_DIR)/usr/bin/curl
endef
LIBCURL_POST_INSTALL_TARGET_HOOKS += LIBCURL_TARGET_CLEANUP
endif

endif
