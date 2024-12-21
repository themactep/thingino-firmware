#define THINGINO_ETHERNET_INSTALL_TARGET_CMDS
#	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
#	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(THINGINO_ETHERNET_PKGDIR)/files/eth0
#endef

ifeq ($(BR2_ETHERNET),y)
define THINGINO_ETHERNET_BUSYBOX_CONFIG_FIXUPS_ETH
        $(call KCONFIG_ENABLE_OPT,CONFIG_IFPLUGD)
endef
endif

define THINGINO_ETHERNET_BUSYBOX_CONFIG_FIXUPS
        $(call KCONFIG_ENABLE_OPT,CONFIG_IFPLUGD)
endef

$(eval $(generic-package))
