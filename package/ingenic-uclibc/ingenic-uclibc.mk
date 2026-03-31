INGENIC_UCLIBC_VERSION = 97c9ba8
INGENIC_UCLIBC_SITE = https://github.com/gtxaspec/ingenic-uclibc
INGENIC_UCLIBC_SITE_METHOD = git
INGENIC_UCLIBC_INSTALL_STAGING = YES

INGENIC_UCLIBC_LICENSE = MIT
INGENIC_UCLIBC_LICENSE_FILES = LICENSE

define INGENIC_UCLIBC_BUILD_CMDS
	$(TARGET_CC) -fPIC -shared -o $(@D)/libuclibcshim.so $(@D)/uclibc_shim.c
endef

define INGENIC_UCLIBC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libuclibcshim.so $(STAGING_DIR)/usr/lib/libuclibcshim.so
endef

define INGENIC_UCLIBC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libuclibcshim.so $(TARGET_DIR)/usr/lib/libuclibcshim.so
endef

$(eval $(generic-package))
