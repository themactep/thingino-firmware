THINGINO_IRCUT_SITE_METHOD = local
THINGINO_IRCUT_SITE = $(BR2_EXTERNAL)/package/thingino-ircut

define THINGINO_IRCUT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/S06ircut $(TARGET_DIR)/etc/init.d/S06ircut
	$(INSTALL) -D -m 0755 $(@D)/files/S07dusk2dawn $(TARGET_DIR)/etc/init.d/S07dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/S08daynight $(TARGET_DIR)/etc/init.d/S08daynight
	$(INSTALL) -D -m 0755 $(@D)/files/daynight $(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(@D)/files/irled $(TARGET_DIR)/usr/sbin/irled
	$(INSTALL) -D -m 0755 $(@D)/files/ircut $(TARGET_DIR)/usr/sbin/ircut
	$(INSTALL) -D -m 0755 $(@D)/files/dusk2dawn $(TARGET_DIR)/usr/sbin/dusk2dawn
endef

$(eval $(generic-package))
