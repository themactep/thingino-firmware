AW87XXX_SITE_METHOD = git
AW87XXX_SITE = https://github.com/gtxaspec/aw87xxx
AW87XXX_SITE_BRANCH = master
AW87XXX_VERSION = 1d7bc5ae8f50c1836acb4b31137f426068e87d70
AW87XXX_LICENSE = GPL-2.0

AW87XXX_MODULE_MAKE_OPTS = CONFIG_SND_SOC_AW87XXX=m

define AW87XXX_INSTALL_EXTRAS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)
	touch $(TARGET_DIR)/lib/modules/$(LINUX_VERSION_PROBED)/modules.builtin.modinfo
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/firmware
	$(INSTALL) -D -m 0644 $(@D)/firmware/aw87xxx_acf.bin \
		$(TARGET_DIR)/usr/lib/firmware/aw87xxx_acf.bin
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc
	grep -qxF snd_soc_aw87xxx $(TARGET_DIR)/etc/modules 2>/dev/null || \
		echo snd_soc_aw87xxx >> $(TARGET_DIR)/etc/modules
	$(INSTALL) -D -m 0755 $(AW87XXX_PKGDIR)/files/S62aw87xxx \
		$(TARGET_DIR)/etc/init.d/S62aw87xxx
endef
AW87XXX_POST_INSTALL_TARGET_HOOKS += AW87XXX_INSTALL_EXTRAS

$(eval $(kernel-module))
$(eval $(generic-package))
