ATBM6441_TOOLS_SITE_METHOD = git
ATBM6441_TOOLS_SITE = https://github.com/CapnRon/atbm6441-tools
ATBM6441_TOOLS_SITE_BRANCH = main
ATBM6441_TOOLS_VERSION = 0cf259c95aca8d060b1584c7dd5f1117bc66a289

ATBM6441_TOOLS_LICENSE = Proprietary
ATBM6441_TOOLS_REDISTRIBUTE = NO

define ATBM6441_TOOLS_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		-Wno-error=return-mismatch -Wno-error=return-type \
		$(@D)/tools.c -lpthread -lrt \
		-o $(@D)/atbm_iot_supplicant_demo

	$(TARGET_CC) $(TARGET_CFLAGS) -I$(@D) \
		-Wno-error=return-mismatch -Wno-error=return-type \
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
