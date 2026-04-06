################################################################################
#
# thingino-cloner - USB flashing tool for Ingenic SoC devices (host tool)
#
################################################################################

THINGINO_CLONER_VERSION = de3ed04ed44686cae59182d84048b7b2af933dcf
THINGINO_CLONER_SITE = $(call github,gtxaspec,thingino-cloner,$(THINGINO_CLONER_VERSION))

THINGINO_CLONER_LICENSE = GPL-2.0
THINGINO_CLONER_LICENSE_FILES = LICENSE

HOST_THINGINO_CLONER_DEPENDENCIES = host-pkgconf host-libusb host-zlib

define HOST_THINGINO_CLONER_INSTALL_FIRMWARES
	mkdir -p $(HOST_DIR)/share/thingino-cloner
	cp -r $(@D)/firmwares $(HOST_DIR)/share/thingino-cloner/
endef

HOST_THINGINO_CLONER_POST_INSTALL_HOOKS += HOST_THINGINO_CLONER_INSTALL_FIRMWARES

$(eval $(host-cmake-package))
