EXFAT_NOFUSE_SITE_METHOD = git
EXFAT_NOFUSE_SITE = https://github.com/dorimanx/exfat-nofuse
EXFAT_NOFUSE_SITE_BRANCH = master
EXFAT_NOFUSE_VERSION = 01c30ad52625a7261e1b0d874553b6ca7af25966

EXFAT_NOFUSE_LICENSE = GPL-2.0+
EXFAT_NOFUSE_LICENSE_FILES = COPYING

define EXFAT_NOFUSE_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) -C $(@D) KDIR=$(LINUX_DIR)
endef

define EXFAT_NOFUSE_INSTALL_TARGET_CMDS
	krel="$$( $(MAKE) -s -C $(LINUX_DIR) kernelrelease 2>/dev/null )"; \
	if [ -z "$$krel" ]; then krel="$(LINUX_VERSION_PROBED)"; fi; \
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/modules/$$krel; \
	touch $(TARGET_DIR)/lib/modules/$$krel/modules.builtin.modinfo; \
	$(INSTALL) -D -m 0644 $(@D)/exfat.ko \
		$(TARGET_DIR)/lib/modules/$$krel/extra/exfat.ko; \
	$(TARGET_STRIP) --strip-debug $(TARGET_DIR)/lib/modules/$$krel/extra/exfat.ko; \
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc; \
	echo exfat >> $(TARGET_DIR)/etc/modules
endef

$(eval $(kernel-module))
$(eval $(generic-package))
