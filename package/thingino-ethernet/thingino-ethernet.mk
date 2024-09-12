#define THINGINO_ETHERNET_INSTALL_TARGET_CMDS
#	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
#	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(THINGINO_ETHERNET_PKGDIR)/files/eth0
#endef

$(eval $(generic-package))
