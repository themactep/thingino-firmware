EXFAT_NOFUSE_VERSION = master
EXFAT_NOFUSE_SITE = $(call github,dorimanx,exfat-nofuse,$(EXFAT_NOFUSE_VERSION))
EXFAT_NOFUSE_LICENSE = GPL-2.0+
EXFAT_NOFUSE_LICENSE_FILES = COPYING

define EXFAT_NOFUSE_BUILD_CMDS
$(MAKE) \
        CROSS_COMPILE=$(TARGET_CROSS) \
        -C $(@D) KDIR=$(LINUX_DIR)
endef

define EXFAT_NOFUSE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/exfat.ko $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))
endef

$(eval $(kernel-module))
$(eval $(generic-package))
