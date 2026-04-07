THINGINO_RAPTOR_IPC_VERSION = 93c3be1
THINGINO_RAPTOR_IPC_SITE = https://github.com/gtxaspec/raptor-ipc
THINGINO_RAPTOR_IPC_SITE_METHOD = git
THINGINO_RAPTOR_IPC_INSTALL_STAGING = YES
THINGINO_RAPTOR_IPC_INSTALL_TARGET = NO

define THINGINO_RAPTOR_IPC_BUILD_CMDS
	$(MAKE) -C $(@D) CC="$(TARGET_CC)" AR="$(TARGET_AR)"
endef

define THINGINO_RAPTOR_IPC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/librss_ipc.a \
		$(STAGING_DIR)/usr/lib/librss_ipc.a
	$(INSTALL) -D -m 0644 $(@D)/include/rss_ipc.h \
		$(STAGING_DIR)/usr/include/rss_ipc.h
endef

$(eval $(generic-package))
