THINGINO_BUTTON_SITE_METHOD = git
THINGINO_BUTTON_SITE = https://github.com/gtxaspec/thingino-button
THINGINO_BUTTON_SITE_BRANCH = master
THINGINO_BUTTON_VERSION = 6a88c8e5fc203ceabc721ad03e2e1be8deb81c80
# $(shell git ls-remote $(THINGINO_BUTTON_SITE) $(THINGINO_BUTTON_SITE_BRANCH) | head -1 | cut -f1)

define CHECK_MULTIPLE_GPIO_BUTTONS
	if [ "$(BR2_THINGINO_DEV_DOORBELL)" != "y" ] && [ "$(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL)" != "y" ]; then \
		button_count=0; \
		while IFS= read -r line; do \
			case "$$line" in \
				gpio_button=*|gpio_button_*=*) \
					button_count=$$((button_count + 1)); \
					;; \
			esac; \
		done < $(U_BOOT_ENV_TXT); \
		if [ "$$button_count" -gt 1 ]; then \
			echo "KEY_1 TIMED 0.1 iac -f /usr/share/sounds/th-chime_1.pcm" >> $(TARGET_DIR)/etc/thingino-button.conf; \
		fi \
	fi
endef

define THINGINO_BUTTON_BUILD_CMDS
	$(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D) thingino-button
endef

define DOORBELL_BUTTON_CONF
	if [ "$(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL)" = "y" ]; then \
		$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc; \
		echo -e "KEY_1 RELEASE 0 doorbell_ctrl $(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL_MAC) 15 1\nKEY_1 TIMED 0.1 iac -f /usr/share/sounds/th-doorbell_3.pcm" \
			>> $(TARGET_DIR)/etc/thingino-button.conf; \
	else \
		if [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
			$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc; \
			echo -e "KEY_1 RELEASE 0 KEY_1 TIMED 0.1 iac -f /usr/share/sounds/th-doorbell_3.pcm" \
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
