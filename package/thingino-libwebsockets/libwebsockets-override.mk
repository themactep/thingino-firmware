################################################################################
#
# libwebsockets overrides for Thingino
#
################################################################################

# Ensure libwebsockets pulls headers from the real zlib provider (libzlib).
# This override applies unconditionally to fix the virtual package dependency.
override LIBWEBSOCKETS_DEPENDENCIES := $(filter-out zlib,$(LIBWEBSOCKETS_DEPENDENCIES)) libzlib

ifeq ($(BR2_PACKAGE_THINGINO_LIBWEBSOCKETS),y)

override LIBWEBSOCKETS_VERSION = 4.5.2

endif
