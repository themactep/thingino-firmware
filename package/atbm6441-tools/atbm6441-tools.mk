ATBM6441_TOOLS_SITE_METHOD = local
ATBM6441_TOOLS_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/atbm6441-tools/files
ATBM6441_TOOLS_VERSION = local

ATBM6441_TOOLS_LICENSE = Proprietary
ATBM6441_TOOLS_REDISTRIBUTE = NO

define ATBM6441_TOOLS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		-Wno-error=return-mismatch -Wno-error=return-type \
		-Wno-error=implicit-function-declaration \
		$(@D)/tools.c -DDEMO_TCP_SEND -lpthread -lrt \
		-o $(@D)/atbm_iot_supplicant_demo

	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		-Wno-error=return-mismatch -Wno-error=return-type \
		-Wno-error=implicit-function-declaration \
		$(@D)/tools_cli.c -lpthread \
		-o $(@D)/atbm_iot_cli
endef

define ATBM6441_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/atbm_iot_supplicant_demo \
		$(TARGET_DIR)/usr/bin/atbm_iot_supplicant_demo
	$(INSTALL) -D -m 0755 $(@D)/atbm_iot_cli \
		$(TARGET_DIR)/usr/bin/atbm_iot_cli
endef

$(eval $(generic-package))
