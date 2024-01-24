################################################################################
#
# ingenic-audiodaemon
#
################################################################################

INGENIC_AUDIODAEMON_SITE_METHOD = git
INGENIC_AUDIODAEMON_SITE = https://github.com/gtxaspec/ingenic_audiodaemon
INGENIC_AUDIODAEMON_VERSION = $(shell git ls-remote $(INGENIC_AUDIODAEMON_SITE) HEAD | head -1 | cut -f1)

INGENIC_AUDIODAEMON_LICENSE = GPL-2.0
INGENIC_AUDIODAEMON_LICENSE_FILES = COPYING

define INGENIC_AUDIODAEMON_BUILD_CMDS
    $(MAKE) CROSS_COMPILE=$(TARGET_CROSS) deps -C $(@D)
    $(MAKE) CROSS_COMPILE=$(TARGET_CROSS) all -C $(@D)
endef

define INGENIC_AUDIODAEMON_INSTALL_TARGET_CMDS
    cp -a $(@D)/build/bin/. $(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))
