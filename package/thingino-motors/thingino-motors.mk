THINGINO_MOTORS_SITE_METHOD = git
THINGINO_MOTORS_SITE = https://github.com/gtxaspec/ingenic-motor.git
THINGINO_MOTORS_SITE_BRANCH = master
THINGINO_MOTORS_VERSION = eec1b96a7dafb18131e261fb950e6c1b6b019c50
# $(shell git ls-remote $(THINGINO_MOTORS_SITE) $(THINGINO_MOTORS_SITE_BRANCH) | head -1 | cut -f1)

THINGINO_MOTORS_LICENSE = MIT
THINGINO_MOTORS_LICENSE_FILES = LICENSE

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),y)
define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin
	$(INSTALL) -m 755 $(THINGINO_MOTORS_PKGDIR)/files/dw9714-ctrl -t $(TARGET_DIR)/usr/sbin
endef
else
define THINGINO_MOTORS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/motor.c -o $(@D)/motors
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/motor-daemon.c -o $(@D)/motors-daemon
endef

define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(THINGINO_MOTORS_PKGDIR)/files/S09motor

	$(INSTALL) -m 755 -D $(@D)/motors $(TARGET_DIR)/usr/bin/motors
	$(INSTALL) -m 755 -D $(@D)/motors-daemon $(TARGET_DIR)/usr/bin/motors-daemon

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin/
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(THINGINO_MOTORS_PKGDIR)/files/ptz-ctrl

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets.conf
endef
endif

$(eval $(generic-package))
