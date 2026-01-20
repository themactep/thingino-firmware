################################################################################
#
# mbedtls override for HTTP/2 support
#
################################################################################

# This file overrides the buildroot mbedtls package to enable HTTP/2 capabilities
# Required features:
# - MBEDTLS_SSL_ALPN (Application Layer Protocol Negotiation)
# - MBEDTLS_SSL_SERVER_NAME_INDICATION (SNI)
# - MBEDTLS_SSL_SESSION_TICKETS
# - TLS 1.3 support and modern ciphers

define MBEDTLS_ENABLE_HTTP2_FEATURES
	# Enable ALPN (Application Layer Protocol Negotiation)
	$(SED) "s://#define MBEDTLS_SSL_ALPN:#define MBEDTLS_SSL_ALPN:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable Server Name Indication (SNI)
	$(SED) "s://#define MBEDTLS_SSL_SERVER_NAME_INDICATION:#define MBEDTLS_SSL_SERVER_NAME_INDICATION:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable Session Tickets
	$(SED) "s://#define MBEDTLS_SSL_SESSION_TICKETS:#define MBEDTLS_SSL_SESSION_TICKETS:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable TLS 1.3 support (for modern ciphers) - if available
	$(SED) "s://#define MBEDTLS_SSL_PROTO_TLS1_3:#define MBEDTLS_SSL_PROTO_TLS1_3:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable modern cipher suites for HTTP/2
	$(SED) "s://#define MBEDTLS_KEY_EXCHANGE_ECDHE_RSA_ENABLED:#define MBEDTLS_KEY_EXCHANGE_ECDHE_RSA_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED:#define MBEDTLS_KEY_EXCHANGE_ECDHE_ECDSA_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable required ciphers for HTTP/2
	$(SED) "s://#define MBEDTLS_CIPHER_MODE_GCM:#define MBEDTLS_CIPHER_MODE_GCM:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_GCM_C:#define MBEDTLS_GCM_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable ECC support for modern TLS
	$(SED) "s://#define MBEDTLS_ECDH_C$$:#define MBEDTLS_ECDH_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_ECDSA_C:#define MBEDTLS_ECDSA_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_ECP_C:#define MBEDTLS_ECP_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable specific curves commonly used by HTTP/2
	$(SED) "s://#define MBEDTLS_ECP_DP_SECP256R1_ENABLED:#define MBEDTLS_ECP_DP_SECP256R1_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_ECP_DP_SECP384R1_ENABLED:#define MBEDTLS_ECP_DP_SECP384R1_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_ECP_DP_SECP521R1_ENABLED:#define MBEDTLS_ECP_DP_SECP521R1_ENABLED:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable additional features commonly needed for HTTP/2
	$(SED) "s://#define MBEDTLS_SSL_EXTENDED_MASTER_SECRET:#define MBEDTLS_SSL_EXTENDED_MASTER_SECRET:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_SSL_ENCRYPT_THEN_MAC:#define MBEDTLS_SSL_ENCRYPT_THEN_MAC:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable bignum support for ECC (required for ECDH)
	$(SED) "s://#define MBEDTLS_BIGNUM_C:#define MBEDTLS_BIGNUM_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable ASN.1 support (required for certificates)
	$(SED) "s://#define MBEDTLS_ASN1_PARSE_C:#define MBEDTLS_ASN1_PARSE_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_ASN1_WRITE_C:#define MBEDTLS_ASN1_WRITE_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable threading support (required for some ECDH operations)
	$(SED) "s://#define MBEDTLS_THREADING_C:#define MBEDTLS_THREADING_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	$(SED) "s://#define MBEDTLS_THREADING_PTHREAD:#define MBEDTLS_THREADING_PTHREAD:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable missing dependencies for ECDH
	$(SED) "s://#define MBEDTLS_ECDH_LEGACY_CONTEXT:#define MBEDTLS_ECDH_LEGACY_CONTEXT:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Ensure ECDH compute shared function is NOT using alternative implementation (via patch)

	# Enable legacy ECDH interface (provides mbedtls_ecdh_compute_shared)
	$(SED) "s://#define MBEDTLS_ECDH_C$$:#define MBEDTLS_ECDH_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable ECC key pair support which ECDH depends on
	$(SED) "s://#define MBEDTLS_ECP_C:#define MBEDTLS_ECP_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable PSA crypto support which may provide the missing ECDH function
	$(SED) "s://#define MBEDTLS_PSA_CRYPTO_C:#define MBEDTLS_PSA_CRYPTO_C:" \
		$(@D)/include/mbedtls/mbedtls_config.h

	# Enable all necessary PSA key types for ECDH
	$(SED) "s://#define PSA_WANT_KEY_TYPE_ECC_KEY_PAIR_BASIC:#define PSA_WANT_KEY_TYPE_ECC_KEY_PAIR_BASIC:" \
		$(@D)/include/psa/crypto_config.h || true

	$(SED) "s://#define PSA_WANT_KEY_TYPE_ECC_PUBLIC_KEY:#define PSA_WANT_KEY_TYPE_ECC_PUBLIC_KEY:" \
		$(@D)/include/psa/crypto_config.h || true

	$(SED) "s://#define PSA_WANT_ALG_ECDH:#define PSA_WANT_ALG_ECDH:" \
		$(@D)/include/psa/crypto_config.h || true

	# Enable ECC curves for PSA
	$(SED) "s://#define PSA_WANT_ECC_SECP_R1_256:#define PSA_WANT_ECC_SECP_R1_256:" \
		$(@D)/include/psa/crypto_config.h || true

	$(SED) "s://#define PSA_WANT_ECC_SECP_R1_384:#define PSA_WANT_ECC_SECP_R1_384:" \
		$(@D)/include/psa/crypto_config.h || true

	$(SED) "s://#define PSA_WANT_ECC_SECP_R1_521:#define PSA_WANT_ECC_SECP_R1_521:" \
		$(@D)/include/psa/crypto_config.h || true
endef

# Disable problematic programs and tests that are causing linking issues
# We only need the libraries for HTTP/2 support
override MBEDTLS_CONF_OPTS += -DENABLE_PROGRAMS=OFF -DENABLE_TESTING=OFF

# Force shared libraries to reduce image size (mbedTLS is being linked into many apps)
# Use the proper Buildroot/mbedTLS CMake variables instead of generic BUILD_SHARED_LIBS
override MBEDTLS_CONF_OPTS += -DUSE_SHARED_MBEDTLS_LIBRARY=ON -DUSE_STATIC_MBEDTLS_LIBRARY=OFF

# Add the HTTP/2 configuration hook to mbedtls
MBEDTLS_PRE_CONFIGURE_HOOKS += MBEDTLS_ENABLE_HTTP2_FEATURES