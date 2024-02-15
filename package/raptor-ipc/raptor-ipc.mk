RAPTOR_IPC_SITE_METHOD = git
RAPTOR_IPC_SITE = https://github.com/gtxaspec/raptor
RAPTOR_IPC_VERSION = $(shell git ls-remote $(RAPTOR_IPC_SITE) rvd-dev | head -1 | cut -f1)

RAPTOR_IPC_LICENSE = GPL-3.0
RAPTOR_IPC_LICENSE_FILES = COPYING

define RAPTOR_IPC_BUILD_CMDS
	$(MAKE) $(RAPTOR_IPC_MAKE_OPTS) CROSS_COMPILE=$(TARGET_CROSS) TARGET=$(SOC_FAMILY) -C $(@D)
endef

define RAPTOR_IPC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/raptor $(TARGET_DIR)/usr/bin/raptor
endef

$(eval $(generic-package))
