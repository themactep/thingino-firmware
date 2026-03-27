LIBIMP_DEBUG_SITE_METHOD = git
LIBIMP_DEBUG_SITE = https://github.com/gtxaspec/libimp-debug
LIBIMP_DEBUG_SITE_BRANCH = main
LIBIMP_DEBUG_VERSION = 026a6549e9a0026536fa87dbb9b33d5f50af4293

define LIBIMP_DEBUG_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D) libimp-debug
endef

define LIBIMP_DEBUG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libimp-debug $(TARGET_DIR)/usr/bin/libimp-debug
endef

$(eval $(generic-package))
