LIBIMP_DEBUG_SITE_METHOD = git
LIBIMP_DEBUG_SITE = https://github.com/gtxaspec/libimp-debug
LIBIMP_DEBUG_SITE_BRANCH = main
LIBIMP_DEBUG_VERSION = 44042d4

define LIBIMP_DEBUG_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D) all
endef

define LIBIMP_DEBUG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libimp-debug $(TARGET_DIR)/usr/bin/libimp-debug
	$(INSTALL) -D -m 0755 $(@D)/libimp-nodbg.so $(TARGET_DIR)/usr/lib/libimp-nodbg.so
endef

$(eval $(generic-package))
