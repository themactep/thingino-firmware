INGENIC_DIAG_TOOLS_SITE_METHOD = git
INGENIC_DIAG_TOOLS_SITE = https://github.com/gtxaspec/jz-diag-tools
INGENIC_DIAG_TOOLS_SITE_BRANCH = main
INGENIC_DIAG_TOOLS_VERSION = $(shell git ls-remote $(INGENIC_DIAG_TOOLS_SITE) $(INGENIC_DIAG_TOOLS_SITE_BRANCH) | head -1 | cut -f1)

define INGENIC_DIAG_TOOLS_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D)
endef

define INGENIC_DIAG_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ingenic-gpio $(TARGET_DIR)/usr/bin/gpio-diag
endef

$(eval $(generic-package))
