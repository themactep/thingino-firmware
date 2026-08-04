INGENIC_UCLIBC_VERSION = e266b12ddab5dc1685d3df3a7723659b97c2f12e
INGENIC_UCLIBC_SITE = https://github.com/gtxaspec/ingenic-uclibc
INGENIC_UCLIBC_SITE_METHOD = git
INGENIC_UCLIBC_INSTALL_STAGING = YES

INGENIC_UCLIBC_LICENSE = MIT
INGENIC_UCLIBC_LICENSE_FILES = LICENSE

INGENIC_UCLIBC_CFLAGS = -Os -ffunction-sections -fdata-sections -flto \
	-fno-asynchronous-unwind-tables -fmerge-all-constants -fno-ident

# GCC 16+: __ctype_*_loc() need explicit prototypes (guarded by
# __UCLIBC_HAS_XLOCALE__ in uClibc-ng headers). Insert them before build.
define INGENIC_UCLIBC_BUILD_CMDS
	# GCC 16+: uClibc-ng already exports __ctype_b / __ctype_tolower /
	# __ctype_toupper as global data symbols.  The shim must not define
	# its own BSS copies (they would shadow libc's and stay zero on
	# MIPS where the main executable / first-loaded library wins).
	# Drop the local BSS declarations and the init_ctype_compat()
	# constructor — libc provides the real pointers.
	sed -i '/^const __ctype_mask_t \*__ctype_b;$$/d' $(@D)/uclibc_shim.c
	sed -i '/^const __ctype_touplow_t \*__ctype_tolower;$$/d' $(@D)/uclibc_shim.c
	sed -i '/^const __ctype_touplow_t \*__ctype_toupper;$$/d' $(@D)/uclibc_shim.c
	sed -i '/^static void.*init_ctype_compat/,/^}$$/d' $(@D)/uclibc_shim.c
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
