################################################################################
#
# mosquitto overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_MOSQUITTO),y)

# Keep Buildroot mosquitto pinned to the version vetted for Thingino.
override MOSQUITTO_VERSION = 2.0.22
override MOSQUITTO_SITE = https://sources.buildroot.net/mosquitto

# Keep client builds lean; disable cJSON/JSON pretty-print support.
override MOSQUITTO_DEPENDENCIES := $(filter-out cjson,$(MOSQUITTO_DEPENDENCIES))
override MOSQUITTO_STATIC_LIBS := $(filter-out -lcjson,$(MOSQUITTO_STATIC_LIBS))
override MOSQUITTO_MAKE_OPTS := $(filter-out WITH_CJSON=%,$(MOSQUITTO_MAKE_OPTS))
override MOSQUITTO_MAKE_OPTS += WITH_CJSON=no

override MOSQUITTO_MAKE_OPTS += prefix=/usr

# Prefer mbedTLS or OpenSSL
ifeq ($(BR2_PACKAGE_THINGINO_MOSQUITTO_USE_MBEDTLS),y)
# Use mbedTLS backend
override MOSQUITTO_DEPENDENCIES := $(filter-out openssl,$(MOSQUITTO_DEPENDENCIES))
override MOSQUITTO_DEPENDENCIES += mbedtls
override MOSQUITTO_STATIC_LIBS := $(filter-out -lssl -lcrypto,$(MOSQUITTO_STATIC_LIBS))
override MOSQUITTO_STATIC_LIBS += -lmbedtls -lmbedx509 -lmbedcrypto
override MOSQUITTO_MAKE_OPTS := $(filter-out WITH_TLS=%,$(MOSQUITTO_MAKE_OPTS))
override MOSQUITTO_MAKE_OPTS += WITH_TLS=yes TLS_IMPL=mbedtls

else ifeq ($(BR2_PACKAGE_OPENSSL),y)
# Use OpenSSL backend as fallback
override MOSQUITTO_DEPENDENCIES += host-pkgconf openssl toolchain-external-custom
override MOSQUITTO_MAKE_OPTS := $(filter-out WITH_TLS=%,$(MOSQUITTO_MAKE_OPTS))
override MOSQUITTO_MAKE_OPTS += WITH_TLS=yes
override MOSQUITTO_STATIC_LIBS += `$(PKG_CONFIG_HOST_BINARY) --libs openssl`
endif

# Unless the Thingino-specific broker option is enabled, skip building the
# upstream broker even though the Buildroot symbol stays default-on.
ifneq ($(BR2_PACKAGE_THINGINO_MOSQUITTO_BROKER),y)

override MOSQUITTO_MAKE_DIRS = lib client

override define MOSQUITTO_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) $(TARGET_CONFIGURE_OPTS) DIRS="$(MOSQUITTO_MAKE_DIRS)" \
		$(MOSQUITTO_MAKE_OPTS) DESTDIR=$(TARGET_DIR) install
	rm -f $(TARGET_DIR)/etc/mosquitto/*.example
endef

override define MOSQUITTO_INSTALL_INIT_SYSV
endef

override define MOSQUITTO_INSTALL_INIT_SYSTEMD
endef

override MOSQUITTO_USERS =

endif # !BR2_PACKAGE_THINGINO_MOSQUITTO_BROKER

endif # BR2_PACKAGE_THINGINO_MOSQUITTO
