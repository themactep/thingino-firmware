THINGINO_MOTORS_SITE_METHOD = git
THINGINO_MOTORS_SITE = https://github.com/themactep/thingino-motors.git
THINGINO_MOTORS_SITE_BRANCH = master
THINGINO_MOTORS_VERSION = 462dbacf1504de9a1e45ccb82e894f5a79d7ea6b
THINGINO_MOTORS_LICENSE = MIT
THINGINO_MOTORS_LICENSE_FILES = LICENSE

THINGINO_MOTORS_DEPENDENCIES += host-thingino-jct thingino-jct

THINGINO_MOTORS_OVERRIDE_FILE = $(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/motors.json

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),y)
define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/dw9714-ctrl \
		$(TARGET_DIR)/usr/sbin/dw9714-ctrl
endef
else
define THINGINO_MOTORS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/src/motor.c -o $(@D)/motors -ljct
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/src/motor-daemon.c -o $(@D)/motors-daemon -ljct
endef

define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/motors \
		$(TARGET_DIR)/usr/bin/motors

	$(INSTALL) -D -m 0755 $(@D)/motors-daemon \
		$(TARGET_DIR)/usr/bin/motors-daemon

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/S59motor \
		$(TARGET_DIR)/etc/init.d/S59motor

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets \
		$(TARGET_DIR)/usr/sbin

	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/ptz-ctrl \
		$(TARGET_DIR)/usr/sbin/ptz-ctrl

	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/ptz_presets.conf \
		$(TARGET_DIR)/etc/ptz_presets.conf

	$(INSTALL) -D -m 0644 $(THINGINO_MOTORS_PKGDIR)/files/motors.json \
		$(TARGET_DIR)/etc/motors.json

	# Apply optional camera override using host jct
	if [ -f "$(THINGINO_MOTORS_OVERRIDE_FILE)" ]; then \
		if [ ! -x "$(HOST_DIR)/bin/jct" ]; then \
			echo "ERROR: host jct tool missing: $(HOST_DIR)/bin/jct"; \
			exit 1; \
		fi; \
		echo "Applying Prudynt override from $(THINGINO_MOTORS_OVERRIDE_FILE)"; \
		echo "$(HOST_DIR)/bin/jct $(TARGET_DIR)/etc/motors.json import "$(THINGINO_MOTORS_OVERRIDE_FILE)";"; \
		$(HOST_DIR)/bin/jct $(TARGET_DIR)/etc/motors.json import "$(THINGINO_MOTORS_OVERRIDE_FILE)"; \
	fi
endef
endif

$(eval $(generic-package))
