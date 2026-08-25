QEMU_INGENIC_VERSION = ingenic-0.4.0
QEMU_INGENIC_LICENSE = GPL-2.0-or-later

ifeq ($(BR2_HOSTARCH),x86_64)
QEMU_INGENIC_ARCH = x86_64
else ifeq ($(BR2_HOSTARCH),aarch64)
QEMU_INGENIC_ARCH = aarch64
endif

QEMU_INGENIC_SOURCE = qemu-system-mipsel-linux-$(QEMU_INGENIC_ARCH).tar.gz
QEMU_INGENIC_SITE = https://github.com/gtxaspec/qemu/releases/download/$(QEMU_INGENIC_VERSION)

HOST_QEMU_INGENIC_DEPENDENCIES = host-patchelf

define HOST_QEMU_INGENIC_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/qemu-system-mipsel $(HOST_DIR)/bin/qemu-system-mipsel
	$(HOST_DIR)/bin/patchelf --set-rpath $(HOST_DIR)/lib $(HOST_DIR)/bin/qemu-system-mipsel
	if [ -d $(@D)/ingenic ]; then \
		cp -r $(@D)/ingenic $(HOST_DIR)/share/qemu-ingenic; \
	fi
endef

$(eval $(host-generic-package))
