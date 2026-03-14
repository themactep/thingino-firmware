################################################################################
#
# mosquitto overrides for Thingino
#
# Mosquitto 2.1.2 uses CMake (CONF_OPTS), replacing the legacy Make build
# that the Buildroot submodule's 2.0.22 uses.
#
# IMPORTANT: do NOT use "override VAR :=" for CONF_OPTS or DEPENDENCIES.
# The override.mk is included before buildroot/package/mosquitto/mosquitto.mk
# runs, so ":=" evaluates immediately against empty variables, and the
# "override" flag then silently blocks all subsequent assignments from
# mosquitto.mk.  Plain "+=" appends correctly and CMake honours the last
# value for any duplicate -D flag.
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_MOSQUITTO),y)

ifeq ($(BR2_PACKAGE_THINGINO_MOSQUITTO_USE_MBEDTLS),y)
# mbedTLS backend: swap OpenSSL for mbedtls; keep cjson for client JSON output.
# -DWITH_TLS=ON overrides mosquitto.mk's -DWITH_TLS=OFF (set when OpenSSL is
# absent). The second inclusion of this file (via BR2_EXTERNAL_MKS, after
# mosquitto.mk has run) ensures this value wins in CMake.
MOSQUITTO_DEPENDENCIES += mbedtls cjson
MOSQUITTO_CONF_OPTS += -DWITH_TLS=ON -DWITH_TLS_BACKEND=mbedtls -DWITH_TLS_PSK=OFF
endif

# Unless the Thingino-specific broker option is enabled, force the broker off.
ifneq ($(BR2_PACKAGE_THINGINO_MOSQUITTO_BROKER),y)

MOSQUITTO_CONF_OPTS += -DWITH_BROKER=OFF -DWITH_PLUGINS=OFF -DWITH_APPS=OFF -DWITH_CTRL_SHELL=OFF
# Strip readline/libedit (and thus ncurses) from the dependency list.
# This file is included twice: once early (before mosquitto.mk, when
# MOSQUITTO_DEPENDENCIES is still empty) and once late via BR2_EXTERNAL_MKS
# after mosquitto.mk has run.  The := ensures we capture the current value,
# so the second inclusion is the one that actually removes readline/libedit.
MOSQUITTO_DEPENDENCIES := $(filter-out readline libedit,$(MOSQUITTO_DEPENDENCIES))

override define MOSQUITTO_INSTALL_INIT_SYSV
endef

override define MOSQUITTO_INSTALL_INIT_SYSTEMD
endef

override MOSQUITTO_USERS =

endif # !BR2_PACKAGE_THINGINO_MOSQUITTO_BROKER

endif # BR2_PACKAGE_THINGINO_MOSQUITTO
