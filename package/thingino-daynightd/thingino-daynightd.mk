THINGINO_DAYNIGHTD_VERSION = 2.0.0
THINGINO_DAYNIGHTD_SITE_METHOD = local
THINGINO_DAYNIGHTD_SITE = $(THINGINO_DAYNIGHTD_PKGDIR)
THINGINO_DAYNIGHTD_LICENSE = GPL-2.0
THINGINO_DAYNIGHTD_LICENSE_FILES = LICENSE

# Dependencies
THINGINO_DAYNIGHTD_DEPENDENCIES += thingino-core thingino-jct host-thingino-jct
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
THINGINO_DAYNIGHTD_DEPENDENCIES += thingino-webui
endif

# Build configuration for embedded MIPS target
THINGINO_DAYNIGHTD_MAKE_OPTS = \
	CC="$(TARGET_CC)" \
	CFLAGS="$(TARGET_CFLAGS) -Os -ffunction-sections -fdata-sections" \
	LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -s" \
	PREFIX=/usr

define THINGINO_DAYNIGHTD_BUILD_CMDS
	$(MAKE) $(THINGINO_DAYNIGHTD_MAKE_OPTS) -C $(@D)/files all
endef

define THINGINO_DAYNIGHTD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/daynightd      $(TARGET_DIR)/usr/bin/daynightd
	$(INSTALL) -D -m 0755 $(@D)/files/S10daynightd   $(TARGET_DIR)/etc/init.d/S10daynightd

	# Userspace control scripts (merged from thingino-daynight)
	$(INSTALL) -D -m 0755 $(@D)/files/S06ircut       $(TARGET_DIR)/etc/init.d/S06ircut
	$(INSTALL) -D -m 0755 $(@D)/files/S07dusk2dawn   $(TARGET_DIR)/etc/init.d/S07dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/daynight       $(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(@D)/files/light          $(TARGET_DIR)/usr/sbin/light
	$(INSTALL) -D -m 0755 $(@D)/files/ircut          $(TARGET_DIR)/usr/sbin/ircut
	$(INSTALL) -D -m 0755 $(@D)/files/dusk2dawn      $(TARGET_DIR)/usr/sbin/dusk2dawn

	# Import daynight defaults into thingino.json
	if [ -f "$(@D)/files/daynightd.json" ] && [ -f "$(TARGET_DIR)/etc/thingino.json" ]; then \
		$(HOST_DIR)/bin/jct "$(TARGET_DIR)/etc/thingino.json" import "$(@D)/files/daynightd.json"; \
	fi
endef

define THINGINO_DAYNIGHTD_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(@D)/files/www/config-photosensing.html \
		$(TARGET_DIR)/var/www/config-photosensing.html
	$(INSTALL) -D -m 0644 $(@D)/files/www/config-dusk2dawn.html \
		$(TARGET_DIR)/var/www/config-dusk2dawn.html
	$(INSTALL) -D -m 0644 $(@D)/files/www/a/config-photosensing.js \
		$(TARGET_DIR)/var/www/a/config-photosensing.js
	$(INSTALL) -D -m 0644 $(@D)/files/www/a/config-dusk2dawn.js \
		$(TARGET_DIR)/var/www/a/config-dusk2dawn.js
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-config-daynight.cgi \
		$(TARGET_DIR)/var/www/x/json-config-daynight.cgi
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-daynight-sun.cgi \
		$(TARGET_DIR)/var/www/x/json-daynight-sun.cgi
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-daynight-sensors.cgi \
		$(TARGET_DIR)/var/www/x/json-daynight-sensors.cgi
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-daynight-history.cgi \
		$(TARGET_DIR)/var/www/x/json-daynight-history.cgi
	$(INSTALL) -D -m 0644 $(@D)/files/daynightd.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/daynightd.webui.json
endef

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
THINGINO_DAYNIGHTD_INSTALL_TARGET_CMDS += $(THINGINO_DAYNIGHTD_INSTALL_WWW_CMDS)
endif

$(eval $(generic-package))
