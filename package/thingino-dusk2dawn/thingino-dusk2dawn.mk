THINGINO_DUSK2DAWN_SITE_METHOD = local
THINGINO_DUSK2DAWN_SITE = $(BR2_EXTERNAL)/package/thingino-dusk2dawn

define THINGINO_DUSK2DAWN_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/S07dusk2dawn \
		$(TARGET_DIR)/etc/init.d/S07dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/daynight \
		$(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(@D)/files/dusk2dawn \
		$(TARGET_DIR)/usr/sbin/dusk2dawn
	$(INSTALL) -D -m 0644 $(@D)/files/www/config-dusk2dawn.html \
		$(TARGET_DIR)/var/www/config-dusk2dawn.html
	$(INSTALL) -D -m 0644 $(@D)/files/www/a/config-dusk2dawn.js \
		$(TARGET_DIR)/var/www/a/config-dusk2dawn.js
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-daynight-sun.cgi \
		$(TARGET_DIR)/var/www/x/json-daynight-sun.cgi
endef

$(eval $(generic-package))
