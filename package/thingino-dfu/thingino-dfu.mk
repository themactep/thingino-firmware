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

define HOST_THINGINO_DFU_INSTALL_UDEV_RULE
	mkdir -p $(HOST_DIR)/lib/udev/rules.d
	cp $(HOST_THINGINO_DFU_PKGDIR)/99-thingino-dfu.rules $(HOST_DIR)/lib/udev/rules.d/
endef

HOST_THINGINO_DFU_POST_INSTALL_HOOKS += HOST_THINGINO_DFU_INSTALL_FIRMWARES
HOST_THINGINO_DFU_POST_INSTALL_HOOKS += HOST_THINGINO_DFU_INSTALL_UDEV_RULE

$(eval $(host-cmake-package))
