################################################################################
#
# libopenssl overrides for Thingino
#
################################################################################

# Thingino's OpenSSL feature policy (formerly configs/fragments/ssl-openssl.fragment,
# now owned by the thingino-ssl virtual package choice).  The fragment used to
# force a set of "safe to disable" algorithms off in .config; Kconfig cannot
# express "off unless explicitly selected" for symbols whose upstream default
# is 'y', so we do it here at the build level instead.
#
# The following are hard-disabled regardless of the Buildroot
# BR2_PACKAGE_LIBOPENSSL_ENABLE_* defaults:
#   MD2, RMD160, WHIRLPOOL, RC2, CAST, Blowfish   - obsolete ciphers
#   SSL3, WEAK_SSL                                 - insecure
#   UNSECURE                                       - unit test / debug
#   QUIC, CMP                                       - unused features
#   PADLOCK_ENGINE, LOADER_ENGINE                  - niche engines
#   SSL_TRACE                                      - debug feature
#
# Everything else (including the essential set selected by the thingino-ssl
# OpenSSL choice: CHACHA, RC4, MD4, DES, PSK, IDEA, SEED, BLAKE2, SSL, ECX,
# ARGON2 and the openssl binary) is driven by the regular Buildroot symbols,
# exactly as upstream libopenssl.mk does.
#
# This file is included via BR2_PACKAGE_OVERRIDE_FILE before buildroot's
# package/*/*.mk, so 'override define' takes ownership of
# LIBOPENSSL_CONFIGURE_CMDS and buildroot's definition is ignored.
ifeq ($(BR2_PACKAGE_LIBOPENSSL),y)

override define LIBOPENSSL_CONFIGURE_CMDS
	cd $(@D); \
		$(TARGET_CONFIGURE_ARGS) \
		$(TARGET_CONFIGURE_OPTS) \
		 CFLAGS="$(LIBOPENSSL_CFLAGS)" \
		./Configure \
			$(LIBOPENSSL_TARGET_ARCH) \
			--prefix=/usr \
			--openssldir=/etc/ssl \
			$(if $(BR2_TOOLCHAIN_HAS_THREADS),threads,no-threads) \
			$(if $(BR2_STATIC_LIBS),no-shared,shared) \
			$(if $(BR2_PACKAGE_CRYPTODEV_LINUX),enable-devcryptoeng) \
			no-rc5 \
			enable-camellia \
			no-docs \
			no-tests \
			no-fuzz-libfuzzer \
			no-fuzz-afl \
			no-afalgeng \
			$(if $(BR2_PACKAGE_LIBOPENSSL_BIN),,no-apps) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENGINES),,no-engine) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_CHACHA),,no-chacha) \
			no-rc2 \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_RC4),,no-rc4) \
			no-md2 \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_MD4),,no-md4) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_MDC2),,no-mdc2) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_BLAKE2),,no-blake2) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_IDEA),,no-idea) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_SEED),,no-seed) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_DES),,no-des) \
			no-rmd160 \
			no-whirlpool \
			no-bf \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_SSL),,no-ssl) \
			no-ssl3 \
			no-weak-ssl-ciphers \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_PSK),,no-psk) \
			no-cast \
			no-unit-test no-crypto-mdebug no-autoerrinit \
			$(if $(BR2_PACKAGE_LIBOPENSSL_DYNAMIC_ENGINE),,no-dynamic-engine ) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_COMP),,no-comp) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_ARGON2),,no-argon2) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_CACHED_FETCH),,no-cached-fetch) \
			no-cmp \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_THREAD_POOL),,no-thread-pool no-default-thread-pool) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_ECX),,no-ecx) \
			no-loadereng \
			no-padlockeng \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_MODULE),,no-module) \
			no-quic \
			$(if $(BR2_PACKAGE_LIBOPENSSL_SECURE_MEMORY),,no-secure-memory) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_SIV),,no-siv) \
			$(if $(BR2_PACKAGE_LIBOPENSSL_ENABLE_SM2_PRECOMP_TABLE),,no-sm2-precomp) \
			no-ssl-trace \
			$(if $(BR2_STATIC_LIBS),zlib,zlib-dynamic) \
			$(if $(BR2_STATIC_LIBS),no-dso)
endef

endif
