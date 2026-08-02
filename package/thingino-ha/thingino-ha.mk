THINGINO_HA_SITE_METHOD = local
THINGINO_HA_SITE = $(THINGINO_HA_PKGDIR)/files
THINGINO_HA_LICENSE = MIT
THINGINO_HA_DEPENDENCIES = thingino-core

define THINGINO_HA_INSTALL_TARGET_CMDS
	# Stage defaults for later merge by thingino-core
	$(INSTALL) -D -m 0644 $(THINGINO_HA_PKGDIR)/files/thingino-ha.json \
		$(TARGET_DIR)/usr/share/thingino-defaults/50-ha.json

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
	$(INSTALL) -D -m 0755 $(@D)/ha-event \
		$(TARGET_DIR)/usr/sbin/ha-event

  # Web UI
  $(INSTALL) -D -m 0644 $(@D)/config-ha.html \
		$(TARGET_DIR)/var/www/config-ha.html
  $(INSTALL) -D -m 0644 $(@D)/config-ha.js \
		$(TARGET_DIR)/var/www/a/config-ha.js
  $(INSTALL) -D -m 0755 $(@D)/json-config-ha.cgi \
		$(TARGET_DIR)/var/www/x/json-config-ha.cgi
endef

$(eval $(generic-package))
