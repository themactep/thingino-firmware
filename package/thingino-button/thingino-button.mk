THINGINO_BUTTON_SITE_METHOD = git
THINGINO_BUTTON_SITE = https://github.com/gtxaspec/thingino-button
THINGINO_BUTTON_SITE_BRANCH = master
THINGINO_BUTTON_VERSION = aa1b572fefdd20063f4c0a1752237a02d35f2f84

define CHECK_MULTIPLE_GPIO_BUTTONS
	if [ "$(BR2_THINGINO_DEV_DOORBELL)" != "y" ] && [ "$(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL)" != "y" ]; then \
		if [ -r $(TARGET_DIR)/etc/thingino.json ]; then \
			button_count=0; \
			if which jct >/dev/null 2>&1; then \
				button_count=$$(jct $(TARGET_DIR)/etc/thingino.json print 2>/dev/null | grep -c '"button_'); \
			fi; \
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
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc; \
		echo -e "KEY_1 RELEASE 0 doorbell_ctrl $(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL_MAC) 15 1\nKEY_1 TIMED 0.1 play /usr/share/sounds/doorbell_3.opus" \
			>> $(TARGET_DIR)/etc/thingino-button.conf; \
	else \
		if [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
			$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc; \
			echo -e "KEY_1 TIMED 0.1 play /usr/share/sounds/doorbell_3.opus" \
				>> $(TARGET_DIR)/etc/thingino-button.conf; \
		fi \
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
