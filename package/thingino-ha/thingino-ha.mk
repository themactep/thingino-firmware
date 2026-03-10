THINGINO_HA_SITE_METHOD = local
THINGINO_HA_SITE = $(THINGINO_HA_PKGDIR)/files
THINGINO_HA_LICENSE = MIT

define THINGINO_HA_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/ha-common \
		$(TARGET_DIR)/usr/share/ha-common
	$(INSTALL) -D -m 0755 $(@D)/S93ha \
		$(TARGET_DIR)/etc/init.d/S93ha
	$(INSTALL) -D -m 0755 $(@D)/ha-daemon \
		$(TARGET_DIR)/usr/sbin/ha-daemon
	$(INSTALL) -D -m 0755 $(@D)/ha-discovery \
		$(TARGET_DIR)/usr/sbin/ha-discovery
	$(INSTALL) -D -m 0755 $(@D)/ha-state \
		$(TARGET_DIR)/usr/sbin/ha-state
	$(INSTALL) -D -m 0755 $(@D)/ha-commands \
		$(TARGET_DIR)/usr/sbin/ha-commands
endef

$(eval $(generic-package))
