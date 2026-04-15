INGENIC_UCLIBC_VERSION = 97c9ba8
INGENIC_UCLIBC_SITE = https://github.com/gtxaspec/ingenic-uclibc
INGENIC_UCLIBC_SITE_METHOD = git
INGENIC_UCLIBC_INSTALL_STAGING = YES

INGENIC_UCLIBC_LICENSE = MIT
INGENIC_UCLIBC_LICENSE_FILES = LICENSE

INGENIC_UCLIBC_CFLAGS = -Os -ffunction-sections -fdata-sections -flto \
	-fno-asynchronous-unwind-tables -fmerge-all-constants -fno-ident

define INGENIC_UCLIBC_BUILD_CMDS
	$(TARGET_CC) $(INGENIC_UCLIBC_CFLAGS) -fPIC -shared -o $(@D)/libuclibcshim.so $(@D)/uclibc_shim.c
	$(TARGET_CC) $(INGENIC_UCLIBC_CFLAGS) -c -o $(@D)/uclibc_shim.o $(@D)/uclibc_shim.c
	$(TARGET_CROSS)gcc-ar rcs $(@D)/libuclibcshim.a $(@D)/uclibc_shim.o
endef

define INGENIC_UCLIBC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libuclibcshim.so $(STAGING_DIR)/usr/lib/libuclibcshim.so
	$(INSTALL) -D -m 0644 $(@D)/libuclibcshim.a $(STAGING_DIR)/usr/lib/libuclibcshim.a
endef

# Raptor links the shim statically — skip .so on device when raptor is the streamer
ifneq ($(BR2_PACKAGE_THINGINO_RAPTOR),y)
define INGENIC_UCLIBC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libuclibcshim.so $(TARGET_DIR)/usr/lib/libuclibcshim.so
endef
endif

$(eval $(generic-package))
