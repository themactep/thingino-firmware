THINGINO_DFU_VERSION = 2.0.0
THINGINO_DFU_LICENSE = GPL-2.0-or-later

# The published binaries rather than a source build. thingino-dfu is Rust, and it
# downloads its USB-boot loaders from a release of gtxaspec/u-boot while it builds;
# neither a cargo toolchain nor a build-time download belongs in a host package. The
# release archive carries the tool and that loader tree together, already paired.
ifeq ($(BR2_HOSTARCH),x86_64)
THINGINO_DFU_ARCH = x86_64
else ifeq ($(BR2_HOSTARCH),aarch64)
THINGINO_DFU_ARCH = aarch64
endif

THINGINO_DFU_SOURCE = thingino-dfu-linux-$(THINGINO_DFU_ARCH).tar.gz
THINGINO_DFU_SITE = https://github.com/thingino/thingino-dfu-rs/releases/download/v$(THINGINO_DFU_VERSION)

# No libusb: the tool talks to usbfs itself. The loader tree goes beside the binary
# because 'make dfu' passes --firmware-dir at it, and the udev rule is what lets a
# non-root user reach a camera in USB boot mode.
define HOST_THINGINO_DFU_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/thingino-dfu $(HOST_DIR)/bin/thingino-dfu
	mkdir -p $(HOST_DIR)/share/thingino-dfu
	cp -r $(@D)/firmware $(HOST_DIR)/share/thingino-dfu/
	mkdir -p $(HOST_DIR)/lib/udev/rules.d
	cp $(HOST_THINGINO_DFU_PKGDIR)/99-thingino-dfu.rules $(HOST_DIR)/lib/udev/rules.d/
endef

$(eval $(host-generic-package))
