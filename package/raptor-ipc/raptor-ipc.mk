RAPTOR_IPC_SITE_METHOD = git
RAPTOR_IPC_SITE = https://github.com/gtxaspec/raptor
RAPTOR_IPC_BRANCH = rvd-dev
RAPTOR_IPC_VERSION = 5efe7fcdfad2143e404a12189174b1ae6c40b266
# $(shell git ls-remote $(RAPTOR_IPC_SITE) $(RAPTOR_IPC_BRANCH) | head -1 | cut -f1)

RAPTOR_IPC_LICENSE = GPL-3.0
RAPTOR_IPC_LICENSE_FILES = COPYING

define RAPTOR_IPC_BUILD_CMDS
	$(MAKE) $(RAPTOR_IPC_MAKE_OPTS) CROSS_COMPILE=$(TARGET_CROSS) \
		TARGET=$(SOC_FAMILY) \
		SOC_FAMILY=$(shell echo $(SOC_FAMILY) | tr a-z A-Z) \
		SENSOR_MODEL=$(shell echo $(SENSOR_MODEL) | tr a-z A-Z) \
		-C $(@D)
endef

define RAPTOR_IPC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/bin $(@D)/raptor
endef

$(eval $(generic-package))
