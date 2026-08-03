THINGINO_GPIO_SITE_METHOD = local
THINGINO_GPIO_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-gpio

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
THINGINO_GPIO_DEPENDENCIES += thingino-webui

define THINGINO_GPIO_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(@D)/files/www/config-gpio.html \
		$(TARGET_DIR)/var/www/config-gpio.html
	$(INSTALL) -D -m 0644 $(@D)/files/www/a/config-gpio.js \
		$(TARGET_DIR)/var/www/a/config-gpio.js
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-config-gpio.cgi \
		$(TARGET_DIR)/var/www/x/json-config-gpio.cgi
	$(INSTALL) -D -m 0755 $(@D)/files/www/x/json-gpio.cgi \
		$(TARGET_DIR)/var/www/x/json-gpio.cgi
	$(INSTALL) -D -m 0644 $(@D)/files/gpio.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/gpio.webui.json
endef
endif

define THINGINO_GPIO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/files/gpio.conf $(TARGET_DIR)/etc/gpio.conf
	$(INSTALL) -D -m 0755 $(@D)/files/S05gpio $(TARGET_DIR)/etc/init.d/S05gpio
	$(THINGINO_GPIO_INSTALL_WWW_CMDS)
endef

define THINGINO_GPIO_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_DEBUG_FS)
endef

define INSTALL_GPIO_CONF
	if [ -n "$(BR2_THINGINO_GPIO_LIST)" ]; then \
		echo "$(BR2_THINGINO_GPIO_LIST)" | tr ',' '\n' | while read gpio; do \
			num=$$(echo "$$gpio" | sed 's/[Oo]$$//'); \
			if echo "$$gpio" | grep -q 'O$$'; then \
				echo "$$num high" >> $(TARGET_DIR)/etc/gpio.conf; \
			else \
				echo "$$num low" >> $(TARGET_DIR)/etc/gpio.conf; \
			fi \
		done \
	fi
endef

THINGINO_GPIO_POST_INSTALL_TARGET_HOOKS += INSTALL_GPIO_CONF
$(eval $(generic-package))
