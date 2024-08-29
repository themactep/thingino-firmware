INGENIC_MUSL_SITE_METHOD = git
INGENIC_MUSL_SITE = https://github.com/gtxaspec/ingenic-musl
INGENIC_MUSL_SITE_BRANCH = master
INGENIC_MUSL_VERSION = $(shell git ls-remote $(INGENIC_MUSL_SITE) $(INGENIC_MUSL_SITE_BRANCH) | head -1 | cut -f1)
INGENIC_MUSL_INSTALL_STAGING = YES

INGENIC_MUSL_LICENSE = GPL-2.0
INGENIC_MUSL_LICENSE_FILES = COPYING

define INGENIC_MUSL_BUILD_CMDS
 	$(TARGET_CC) -fPIC -shared -o $(@D)/libmuslshim.so $(@D)/musl_shim.c
endef

define INGENIC_MUSL_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libmuslshim.so $(STAGING_DIR)/usr/lib/libmuslshim.so
endef

define INGENIC_MUSL_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libmuslshim.so $(TARGET_DIR)/usr/lib/libmuslshim.so
endef

$(eval $(generic-package))
