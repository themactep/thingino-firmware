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

define THINGINO_BUTTON_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/thingino-button $(TARGET_DIR)/usr/bin/thingino-button

	$(INSTALL) -D -m 0755 $(THINGINO_BUTTON_PKGDIR)/files/S15thingino-button \
		$(TARGET_DIR)/etc/init.d/S15thingino-button

	$(INSTALL) -D -m 0644 $(THINGINO_BUTTON_PKGDIR)/files/thingino-button.conf \
		$(TARGET_DIR)/etc/thingino-button.conf

	$(DOORBELL_BUTTON_CONF)
	$(CHECK_MULTIPLE_GPIO_BUTTONS)
endef

$(eval $(generic-package))
