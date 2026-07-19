THINGINO_FLOODLIGHTD_VERSION = 1.0.0
THINGINO_FLOODLIGHTD_SITE_METHOD = local
THINGINO_FLOODLIGHTD_SITE = $(THINGINO_FLOODLIGHTD_PKGDIR)
THINGINO_FLOODLIGHTD_LICENSE = GPL-2.0

THINGINO_FLOODLIGHTD_MAKE_OPTS = \
	CC="$(TARGET_CC)" \
	CFLAGS="$(TARGET_CFLAGS) -Wall -Wextra -O2 -std=c99 -D_GNU_SOURCE -ffunction-sections -fdata-sections -DNDEBUG" \
	LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -s"

define THINGINO_FLOODLIGHTD_BUILD_CMDS
	$(MAKE) $(THINGINO_FLOODLIGHTD_MAKE_OPTS) -C $(@D)/files clean
	$(MAKE) $(THINGINO_FLOODLIGHTD_MAKE_OPTS) -C $(@D)/files all
endef

define THINGINO_FLOODLIGHTD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/files/floodlightd    $(TARGET_DIR)/usr/bin/floodlightd
	ln -sf floodlightd $(TARGET_DIR)/usr/bin/floodlightctl
	$(INSTALL) -D -m 0755 $(@D)/files/S96floodlightd $(TARGET_DIR)/etc/init.d/S96floodlightd
	$(INSTALL) -D -m 0755 $(@D)/files/motion.sh      $(TARGET_DIR)/etc/floodlightd/motion.sh
	$(INSTALL) -D -m 0644 $(@D)/files/floodlightd.conf $(TARGET_DIR)/etc/floodlightd.conf
endef

$(eval $(generic-package))
