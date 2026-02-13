################################################################################
#
# libwebsockets overrides for Thingino
#
################################################################################

# Ensure libwebsockets pulls headers from the real zlib provider (libzlib).
# This override applies unconditionally to fix the virtual package dependency.
# Since this runs before buildroot's libwebsockets.mk, we must explicitly
# include dependencies that buildroot would add conditionally (like mbedtls).
override LIBWEBSOCKETS_DEPENDENCIES := $(filter-out zlib,$(LIBWEBSOCKETS_DEPENDENCIES)) libzlib mbedtls

ifeq ($(BR2_PACKAGE_THINGINO_LIBWEBSOCKETS),y)

override LIBWEBSOCKETS_VERSION = 4.5.2

endif
