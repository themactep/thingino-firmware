ATBM6441_TOOLS_SITE_METHOD = local
ATBM6441_TOOLS_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/atbm6441-tools/files
ATBM6441_TOOLS_VERSION = local

ATBM6441_TOOLS_LICENSE = Proprietary
ATBM6441_TOOLS_REDISTRIBUTE = NO

ATBM6441_TOOLS_DEPENDENCIES = linux

define ATBM6441_TOOLS_BUILD_CMDS
	# Build atbm_iot_supplicant_demo with DEMO_TCP_SEND for full feature set
	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		-Wno-error=return-mismatch -Wno-error=return-type \
		-Wno-error=implicit-function-declaration \
		$(@D)/tools.c -DDEMO_TCP_SEND -lpthread -lrt \
		-o $(@D)/atbm_iot_supplicant_demo

	# Build atbm_iot_cli
	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		-Wno-error=return-mismatch -Wno-error=return-type \
		-Wno-error=implicit-function-declaration \
		$(@D)/tools_cli.c -lpthread \
		-o $(@D)/atbm_iot_cli

	# Build pir_daemon (PIR-over-UART0 -> rod OSD status)
	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		$(@D)/pir_daemon.c \
		-o $(@D)/pir_daemon
endef

define ATBM6441_TOOLS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/atbm_iot_supplicant_demo \
		$(TARGET_DIR)/usr/bin/atbm_iot_supplicant_demo
	$(INSTALL) -D -m 0755 $(@D)/atbm_iot_cli \
		$(TARGET_DIR)/usr/bin/atbm_iot_cli
	$(INSTALL) -D -m 0755 $(@D)/pir_daemon \
		$(TARGET_DIR)/usr/bin/pir_daemon
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_THINGINO_PATH)/package/atbm6441-tools/files/S32pir_daemon \
		$(TARGET_DIR)/etc/init.d/S32pir_daemon
endef

$(eval $(generic-package))
