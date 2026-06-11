################################################################################
#
# thingino-dfu - USB flashing tool for Ingenic SoC devices (host tool)
#
################################################################################

THINGINO_DFU_VERSION = 31480d96c8914e6061015de611105c2e0cbcce47
THINGINO_DFU_SITE = $(call github,wltechblog,thingino-dfu,$(THINGINO_DFU_VERSION))

THINGINO_DFU_LICENSE = GPL-2.0
THINGINO_DFU_LICENSE_FILES = LICENSE

HOST_THINGINO_DFU_DEPENDENCIES = host-pkgconf host-libusb host-zlib

define HOST_THINGINO_DFU_INSTALL_FIRMWARES
	mkdir -p $(HOST_DIR)/share/thingino-dfu
	cp -r $(@D)/firmware $(HOST_DIR)/share/thingino-dfu/
endef

HOST_THINGINO_DFU_POST_INSTALL_HOOKS += HOST_THINGINO_DFU_INSTALL_FIRMWARES

$(eval $(host-cmake-package))
