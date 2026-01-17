THINGINO_DUSK2DAWN_SITE_METHOD = local
THINGINO_DUSK2DAWN_SITE = $(BR2_EXTERNAL)/package/thingino-dusk2dawn

define THINGINO_DUSK2DAWN_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/S07dusk2dawn \
		$(TARGET_DIR)/etc/init.d/S07dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/daynight \
		$(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(@D)/files/dusk2dawn \
		$(TARGET_DIR)/usr/sbin/dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/config-dusk2dawn.cgi \
		$(TARGET_DIR)/var/www/x/config-dusk2dawn.cgi
endef

$(eval $(generic-package))
