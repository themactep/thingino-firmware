THINGINO_MOTORS_SITE_METHOD = git
THINGINO_MOTORS_SITE = https://github.com/themactep/thingino-motors.git
THINGINO_MOTORS_SITE_BRANCH = master
THINGINO_MOTORS_VERSION = a4ba420815944ec10612697ba1d21f98aef49a16
THINGINO_MOTORS_LICENSE = MIT
THINGINO_MOTORS_LICENSE_FILES = LICENSE

THINGINO_MOTORS_DEPENDENCIES += host-thingino-jct thingino-jct

define THINGINO_MOTORS_INSTALL_JSON_CMDS
	# Import base motors defaults into thingino.json
	if [ -f "$(THINGINO_MOTORS_PKGDIR)/files/motors.json" ] && [ -f "$(TARGET_DIR)/etc/thingino.json" ]; then \
		$(HOST_DIR)/bin/jct "$(TARGET_DIR)/etc/thingino.json" import "$(THINGINO_MOTORS_PKGDIR)/files/motors.json"; \
	fi

	# Apply user motors overrides
	if [ -n "$(THINGINO_USER_MOTORS_JSON_FILES)" ]; then \
		if [ ! -x "$(HOST_DIR)/bin/jct" ]; then \
			echo "ERROR: host jct tool missing: $(HOST_DIR)/bin/jct"; \
			exit 1; \
		fi; \
	fi
	for USER_MOTORS_CONFIG in $(THINGINO_USER_MOTORS_JSON_FILES); do \
		if [ -s "$$USER_MOTORS_CONFIG" ]; then \
			echo "Applying user motors override from $$USER_MOTORS_CONFIG"; \
			echo "$(HOST_DIR)/bin/jct $(TARGET_DIR)/etc/thingino.json import \"$$USER_MOTORS_CONFIG\""; \
			$(HOST_DIR)/bin/jct "$(TARGET_DIR)/etc/thingino.json" import "$$USER_MOTORS_CONFIG"; \
		fi; \
	done
endef

ifeq ($(BR2_PACKAGE_THINGINO_MOTORS_DW9714_ONLY),y)
define THINGINO_MOTORS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_MOTORS_PKGDIR)/files/dw9714-ctrl \
		$(TARGET_DIR)/usr/sbin/dw9714-ctrl

	$(THINGINO_MOTORS_INSTALL_JSON_CMDS)
endef
else
define THINGINO_MOTORS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/src/motor.c -o $(@D)/motors -ljct
	$(TARGET_CC) $(TARGET_LDFLAGS) -Os -s $(@D)/src/motor-daemon.c -o $(@D)/motors-daemon -ljct -lm
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

	$(THINGINO_MOTORS_INSTALL_JSON_CMDS)
endef
endif

$(eval $(generic-package))
