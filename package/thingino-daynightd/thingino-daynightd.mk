THINGINO_DAYNIGHTD_VERSION = 1.0.0
THINGINO_DAYNIGHTD_SITE_METHOD = local
THINGINO_DAYNIGHTD_SITE = $(THINGINO_DAYNIGHTD_PKGDIR)
THINGINO_DAYNIGHTD_LICENSE = GPL-2.0
THINGINO_DAYNIGHTD_LICENSE_FILES = LICENSE

# Dependencies
THINGINO_DAYNIGHTD_DEPENDENCIES += thingino-jct

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
	$(INSTALL) -D -m 0755 $(@D)/files/daynight       $(TARGET_DIR)/usr/sbin/daynight
	$(INSTALL) -D -m 0644 $(@D)/files/daynightd.json $(TARGET_DIR)/etc/daynightd.json
	$(INSTALL) -D -m 0755 $(@D)/files/S97daynightd   $(TARGET_DIR)/etc/init.d/S97daynightd
endef

$(eval $(generic-package))
