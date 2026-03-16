INGENIC_UCLIBC_INSTALL_STAGING = YES

INGENIC_UCLIBC_LICENSE = GPL-2.0

define INGENIC_UCLIBC_BUILD_CMDS
	$(TARGET_CC) -fPIC -shared -o $(@D)/libuclibcshim.so \
		$(INGENIC_UCLIBC_PKGDIR)/ingenic_shim.c
endef

define INGENIC_UCLIBC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libuclibcshim.so $(STAGING_DIR)/usr/lib/libuclibcshim.so
endef

define INGENIC_UCLIBC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libuclibcshim.so $(TARGET_DIR)/usr/lib/libuclibcshim.so
endef

$(eval $(generic-package))
