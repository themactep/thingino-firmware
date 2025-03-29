THINGINO_MOTORS_SITE_METHOD = git
THINGINO_MOTORS_SITE = https://github.com/gtxaspec/ingenic-motor.git
THINGINO_MOTORS_SITE_BRANCH = master
THINGINO_MOTORS_VERSION = eec1b96a7dafb18131e261fb950e6c1b6b019c50
# $(shell git ls-remote $(THINGINO_MOTORS_SITE) $(THINGINO_MOTORS_SITE_BRANCH) | head -1 | cut -f1)

THINGINO_MOTORS_LICENSE = MIT
THINGINO_MOTORS_LICENSE_FILES = LICENSE

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),y)
define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/dw9714-ctrl \
		$(TARGET_DIR)/usr/sbin/dw9714-ctrl
endef
else
define THINGINO_MOTORS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/motor.c -o $(@D)/motors
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/motor-daemon.c -o $(@D)/motors-daemon
endef

define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/motors \
		$(TARGET_DIR)/usr/bin/motors

	$(INSTALL) -D -m 0755 $(@D)/motors-daemon \
		$(TARGET_DIR)/usr/bin/motors-daemon

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/S09motor \
		$(TARGET_DIR)/etc/init.d/S09motor

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets \
		$(TARGET_DIR)/usr/sbin

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/ptz-ctrl \
		$(TARGET_DIR)/usr/sbin/ptz-ctrl

	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets.conf \
		$(TARGET_DIR)/etc/ptz_presets.conf
endef
endif

$(eval $(generic-package))
