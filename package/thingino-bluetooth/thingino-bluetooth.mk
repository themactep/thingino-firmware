################################################################################
#
# thingino-bluetooth
#
################################################################################

THINGINO_BLUETOOTH_SITE = $(BR2_EXTERNAL)/package/thingino-bluetooth
THINGINO_BLUETOOTH_SITE_METHOD = local
THINGINO_BLUETOOTH_LICENSE = MIT
THINGINO_BLUETOOTH_LICENSE_FILES = LICENSE

THINGINO_BLUETOOTH_DEPENDENCIES = thingino-libble

ifeq ($(BR2_PACKAGE_THINGINO_BLUETOOTH_PROVISIONING),y)
define THINGINO_BLUETOOTH_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D)/src \
		CROSS_COMPILE=$(TARGET_CROSS) \
		LIBBLE_ROOT=$(STAGING_DIR)/usr \
		all
endef

define THINGINO_BLUETOOTH_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/src/ble-provision \
		$(TARGET_DIR)/usr/bin/ble-provision
	$(INSTALL) -D -m 0755 $(@D)/files/S61ble-provision \
		$(TARGET_DIR)/etc/init.d/S61ble-provision
endef
endif

$(eval $(generic-package))
