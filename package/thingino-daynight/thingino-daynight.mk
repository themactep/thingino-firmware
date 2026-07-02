THINGINO_DAYNIGHT_SITE_METHOD = local
THINGINO_DAYNIGHT_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-daynight

define THINGINO_DAYNIGHT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/S06ircut $(TARGET_DIR)/etc/init.d/S06ircut
	$(INSTALL) -D -m 0755 $(@D)/files/S07dusk2dawn $(TARGET_DIR)/etc/init.d/S07dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/daynight $(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(@D)/files/light $(TARGET_DIR)/usr/sbin/light
	$(INSTALL) -D -m 0755 $(@D)/files/ircut $(TARGET_DIR)/usr/sbin/ircut
	$(INSTALL) -D -m 0755 $(@D)/files/dusk2dawn $(TARGET_DIR)/usr/sbin/dusk2dawn
endef

$(eval $(generic-package))
