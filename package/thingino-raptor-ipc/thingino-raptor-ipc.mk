THINGINO_RAPTOR_IPC_VERSION = 682a6f9
THINGINO_RAPTOR_IPC_SITE = https://github.com/gtxaspec/raptor-ipc
THINGINO_RAPTOR_IPC_SITE_METHOD = git
THINGINO_RAPTOR_IPC_INSTALL_STAGING = YES
THINGINO_RAPTOR_IPC_INSTALL_TARGET = YES

define THINGINO_RAPTOR_IPC_BUILD_CMDS
	$(MAKE) -C $(@D) CC="$(TARGET_CC)"
endef

define THINGINO_RAPTOR_IPC_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/librss_ipc.so \
		$(STAGING_DIR)/usr/lib/librss_ipc.so
	$(INSTALL) -D -m 0644 $(@D)/include/rss_ipc.h \
		$(STAGING_DIR)/usr/include/rss_ipc.h
endef

define THINGINO_RAPTOR_IPC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/librss_ipc.so \
		$(TARGET_DIR)/usr/lib/librss_ipc.so
endef

$(eval $(generic-package))
