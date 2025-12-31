INGENIC_LIBIMP_CONTROL_SITE_METHOD = git
INGENIC_LIBIMP_CONTROL_SITE = https://github.com/gtxaspec/libimp_control
INGENIC_LIBIMP_CONTROL_SITE_BRANCH = classic
INGENIC_LIBIMP_CONTROL_VERSION = afba003df82c38c52c2abf979fc38d7983e54b25

define INGENIC_LIBIMP_CONTROL_BUILD_CMDS
	$(MAKE) CONFIG_SOC=$(SOC_FAMILY) CROSS_COMPILE=$(TARGET_CROSS) LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define INGENIC_LIBIMP_CONTROL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libimp_control.so \
		$(TARGET_DIR)/usr/lib/libimp_control.so

	$(INSTALL) -D -m 0755 $(INGENIC_LIBIMP_CONTROL_PKGDIR)/files/imp-control \
		$(TARGET_DIR)/usr/sbin/imp-control

	$(INSTALL) -D -m 0755 $(INGENIC_LIBIMP_CONTROL_PKGDIR)/files/S33impconfig \
		$(TARGET_DIR)/etc/init.d/S33impconfig
endef

$(eval $(generic-package))
