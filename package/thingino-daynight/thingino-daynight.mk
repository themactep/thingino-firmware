THINGINO_DAYNIGHT_VERSION = 1.0.0
THINGINO_DAYNIGHT_SITE_METHOD = local
THINGINO_DAYNIGHT_SITE = $(THINGINO_DAYNIGHT_PKGDIR)
THINGINO_DAYNIGHT_LICENSE = GPL-2.0
THINGINO_DAYNIGHT_LICENSE_FILES = LICENSE

# Dependencies
THINGINO_DAYNIGHT_DEPENDENCIES += cjson

# Build configuration for embedded MIPS target
THINGINO_DAYNIGHT_MAKE_OPTS = \
	CC="$(TARGET_CC)" \
	CFLAGS="$(TARGET_CFLAGS) -Os -ffunction-sections -fdata-sections" \
	LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -s" \
	PREFIX=/usr

define THINGINO_DAYNIGHT_BUILD_CMDS
	$(MAKE) $(THINGINO_DAYNIGHT_MAKE_OPTS) -C $(@D)/files all
endef

define THINGINO_DAYNIGHT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/daynightd \
		$(TARGET_DIR)/usr/bin/daynightd
	$(INSTALL) -D -m 0644 $(@D)/files/daynightd.json \
		$(TARGET_DIR)/etc/daynightd.json
	$(INSTALL) -D -m 0755 $(@D)/files/daynight \
		$(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0755 $(@D)/files/S07dusk2dawn \
		$(TARGET_DIR)/etc/init.d/S07dusk2dawn
	$(INSTALL) -D -m 0755 $(@D)/files/S97daynightd \
		$(TARGET_DIR)/etc/init.d/S97daynightd
	$(INSTALL) -D -m 0755 $(@D)/files/ircut \
		$(TARGET_DIR)/usr/sbin/ircut
	$(INSTALL) -D -m 0755 $(@D)/files/irled \
		$(TARGET_DIR)/usr/sbin/irled
	$(INSTALL) -D -m 0755 $(@D)/files/dusk2dawn \
		$(TARGET_DIR)/usr/sbin/dusk2dawn
endef

$(eval $(generic-package))
