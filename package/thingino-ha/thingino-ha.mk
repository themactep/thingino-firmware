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
	$(INSTALL) -D -m 0755 $(@D)/ha-watchdog \
		$(TARGET_DIR)/usr/sbin/ha-watchdog

  # Web UI
  $(INSTALL) -D -m 0644 $(@D)/config-ha.html \
		$(TARGET_DIR)/var/www/config-ha.html
  $(INSTALL) -D -m 0644 $(@D)/config-ha.js \
		$(TARGET_DIR)/var/www/a/config-ha.js
  $(INSTALL) -D -m 0755 $(@D)/json-config-ha.cgi \
		$(TARGET_DIR)/var/www/x/json-config-ha.cgi

	# Auto-enable doorbell entity on doorbell-equipped cameras
	$(if $(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL),
		printf '{"ha":{"enable_doorbell":true}}\n' > $(TARGET_DIR)/usr/share/thingino-defaults/55-ha-doorbell.json)
endef

$(eval $(generic-package))
