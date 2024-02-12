RAPTOR_IPC_SITE_METHOD = git
RAPTOR_IPC_SITE = https://github.com/gtxaspec/raptor
RAPTOR_IPC_VERSION = $(shell git ls-remote $(RAPTOR_IPC_SITE) HEAD | head -1 | cut -f1)
RAPTOR_IPC_LICENSE = GPL-3.0
RAPTOR_IPC_LICENSE_FILES = COPYING

define RAPTOR_IPC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(RAPTOR_IPC_PKGDIR)/files/$(SOC_FAMILY)/raptor
endef

$(eval $(generic-package))
