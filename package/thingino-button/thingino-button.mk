THINGINO_BUTTON_SITE_METHOD = git
THINGINO_BUTTON_SITE = https://github.com/gtxaspec/thingino-button
THINGINO_BUTTON_SITE_BRANCH = master
THINGINO_BUTTON_VERSION = aa1b572fefdd20063f4c0a1752237a02d35f2f84
# host-thingino-jct provides the jct tool used below; without this
# dependency a bare `which jct` could miss it and silently drop the
# multi-button chime rule.
THINGINO_BUTTON_DEPENDENCIES = host-thingino-jct

THINGINO_BUTTON_JCT = $(HOST_DIR)/bin/jct

# Count the board's buttons in the camera's own config file, NOT in
# $(TARGET_DIR)/etc/thingino.json: thingino-core installs only
# configs/common.thingino.json there and merges the camera json in a
# target-finalize hook that runs after every package has installed, so with
# per-package directories the target copy carries no gpio section at all and
# this count was always zero - the rule below has never been added to any
# board. Same reason ingenic-sdk.mk reads the camera config for its button
# and speaker pins.
THINGINO_BUTTON_CAMERA_JSON = $(BR2_EXTERNAL_THINGINO_PATH)/$(CAMERA_SUBDIR)/$(CAMERA)/thingino.json

# The daemon reads the gpio-keys device through evdev. INPUT_KEYBOARD turns
# on the PC AT keyboard by default, which drags in serio and an i8042 probe.
define THINGINO_BUTTON_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_INPUT_EVDEV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_INPUT_KEYBOARD)
	$(call KCONFIG_ENABLE_OPT,CONFIG_KEYBOARD_GPIO)
	$(call KCONFIG_DISABLE_OPT,CONFIG_KEYBOARD_ATKBD)
endef

# 3.10 gets its keys from ingenic-sdk's gpio-userkeys module; 4.4 describes
# them in the device tree instead.
ifeq ($(BR2_PACKAGE_THINGINO_BUTTON)$(KERNEL_VERSION),y4.4.94)
define THINGINO_BUTTON_LINUX_DT_KEYS
	$(THINGINO_BUTTON_PKGDIR)/inject-button-dt.sh \
		$(THINGINO_BUTTON_CAMERA_JSON) $(LINUX_DIR)
endef
LINUX_PRE_BUILD_HOOKS += THINGINO_BUTTON_LINUX_DT_KEYS
endif

define CHECK_MULTIPLE_GPIO_BUTTONS
	if [ "$(BR2_THINGINO_DEV_DOORBELL)" != "y" ] && [ "$(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL)" != "y" ]; then \
		if [ -r $(THINGINO_BUTTON_CAMERA_JSON) ]; then \
			if [ ! -x $(THINGINO_BUTTON_JCT) ]; then \
				echo "ERROR: host jct tool missing: $(THINGINO_BUTTON_JCT)"; exit 1; \
			fi; \
			button_count=$$($(THINGINO_BUTTON_JCT) $(THINGINO_BUTTON_CAMERA_JSON) print 2>/dev/null | grep -c '"button_'); \
			if [ "$$button_count" -gt 1 ]; then \
				echo "KEY_1 TIMED 0.1 play /usr/share/sounds/chime_1.opus" \
					>> $(TARGET_DIR)/etc/thingino-button.conf; \
			fi \
		fi \
	fi
endef

define THINGINO_BUTTON_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D) thingino-button
endef

define DOORBELL_BUTTON_CONF
	if [ "$(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL)" = "y" ]; then \
		: ; \
	elif [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc; \
		echo -e "KEY_1 TIMED 0.1 play /usr/share/sounds/doorbell_3.opus" \
			>> $(TARGET_DIR)/etc/thingino-button.conf; \
	fi
endef

# Novatek's RTC driver reports ignition as KEY_PROG1; the ignition script only acts when
# thingino.json sets ignition.off_delay.
ifeq ($(SOC_VENDOR),novatek)
define IGNITION_BUTTON_CONF
	$(INSTALL) -D -m 0755 $(THINGINO_BUTTON_PKGDIR)/files/ignition $(TARGET_DIR)/usr/sbin/ignition
	printf 'KEY_PROG1 RELEASE 0 ignition off\nKEY_PROG1 PRESS 0 ignition on\n' \
		>> $(TARGET_DIR)/etc/thingino-button.conf
endef
endif

# A dashcam's short press protects the moment (an event clip) instead of
# speaking the IP; holding the power button shuts down cleanly before the
# RTC's own hold timer cuts the power mid-write.
ifeq ($(BR2_THINGINO_DEV_DASHCAM),y)
define DASHCAM_BUTTON_CONF
	sed -i 's|^KEY_ENTER TIMED 0.1 tell %ip$$|KEY_ENTER TIMED 0.1 raptorctl rtd event|' \
		$(TARGET_DIR)/etc/thingino-button.conf
	printf 'KEY_POWER TIMED_FIRE 2 play /usr/share/sounds/chime_1.opus\nKEY_POWER TIMED 2 touch /run/poweroff; poweroff\n' \
		>> $(TARGET_DIR)/etc/thingino-button.conf
endef
endif

define THINGINO_BUTTON_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/thingino-button $(TARGET_DIR)/usr/bin/thingino-button

	$(INSTALL) -D -m 0755 $(THINGINO_BUTTON_PKGDIR)/files/S15thingino-button \
		$(TARGET_DIR)/etc/init.d/S15thingino-button

	$(INSTALL) -D -m 0644 $(THINGINO_BUTTON_PKGDIR)/files/thingino-button.conf \
		$(TARGET_DIR)/etc/thingino-button.conf

	$(DOORBELL_BUTTON_CONF)
	$(CHECK_MULTIPLE_GPIO_BUTTONS)
	$(IGNITION_BUTTON_CONF)
	$(DASHCAM_BUTTON_CONF)
endef

$(eval $(generic-package))
