THINGINO_GPIO_SITE_METHOD = local
THINGINO_GPIO_SITE = $(BR2_EXTERNAL)/package/thingino-gpio

define THINGINO_GPIO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/files/gpio.conf $(TARGET_DIR)/etc/gpio.conf
	$(INSTALL) -D -m 0755 $(@D)/files/S05gpio $(TARGET_DIR)/etc/init.d/S05gpio
	$(INSTALL) -D -m 0755 $(@D)/files/gpio $(TARGET_DIR)/usr/sbin/gpio
endef

define INSTALL_GPIO_CONF
	if [ -n "$(BR2_GPIO_LIST)" ]; then \
		echo "$(BR2_GPIO_LIST)" | tr ',' '\n' | while read gpio; do \
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
