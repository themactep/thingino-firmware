EXFAT_NOFUSE_SITE_METHOD = git
EXFAT_NOFUSE_SITE = https://github.com/dorimanx/exfat-nofuse
EXFAT_NOFUSE_SITE_BRANCH = master
EXFAT_NOFUSE_VERSION = 01c30ad52625a7261e1b0d874553b6ca7af25966
# $(shell git ls-remote $(EXFAT_NOFUSE_SITE) $(EXFAT_NOFUSE_SITE_BRANCH) | head -1 | cut -f1)

EXFAT_NOFUSE_LICENSE = GPL-2.0+
EXFAT_NOFUSE_LICENSE_FILES = COPYING

define EXFAT_NOFUSE_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) -C $(@D) KDIR=$(LINUX_DIR)
endef

TARGET_MODULES_PATH = $(TARGET_DIR)/lib/modules/$(FULL_KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))
define EXFAT_NOFUSE_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_MODULES_PATH)
	touch $(TARGET_MODULES_PATH)/modules.builtin.modinfo
	$(INSTALL) -m 755 -d $(TARGET_MODULES_PATH)/extra
	$(INSTALL) -m 0644 -t $(TARGET_MODULES_PATH)/extra/ $(@D)/exfat.ko
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	echo exfat >> $(TARGET_DIR)/etc/modules
endef

$(eval $(kernel-module))
$(eval $(generic-package))
