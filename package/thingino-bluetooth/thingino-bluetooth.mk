################################################################################
#
# thingino-bluetooth
#
################################################################################

THINGINO_BLUETOOTH_VERSION = 1.0
THINGINO_BLUETOOTH_SITE_METHOD = local
THINGINO_BLUETOOTH_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-bluetooth


define THINGINO_BLUETOOTH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_BLUETOOTH_PKGDIR)/files/S39bluetooth \
		$(TARGET_DIR)/etc/init.d/S39bluetooth
endef

$(eval $(generic-package))
