ATBM6461_TOOLS_SITE_METHOD = local
ATBM6461_TOOLS_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/atbm6461-tools
ATBM6461_TOOLS_VERSION = local

ATBM6461_TOOLS_LICENSE = MIT
ATBM6461_TOOLS_DEPENDENCIES = wifi-atbm6461

define ATBM6461_TOOLS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -Wall -Wextra -o $(@D)/atbm6461-tool \
		$(@D)/files/atbm6461-tool.c \
		-L$(BR2_EXTERNAL_THINGINO_PATH)/package/wifi-atbm6461/files -lrtos \
		$(TARGET_LDFLAGS)
endef

define ATBM6461_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/atbm6461-tool \
		$(TARGET_DIR)/usr/bin/atbm6461-tool
	ln -sf atbm6461-tool $(TARGET_DIR)/usr/bin/mcu_test
	ln -sf atbm6461-tool $(TARGET_DIR)/usr/bin/atbm6461-battery
	ln -sf atbm6461-tool $(TARGET_DIR)/usr/bin/atbm6461-battery-probe
endef

$(eval $(generic-package))
