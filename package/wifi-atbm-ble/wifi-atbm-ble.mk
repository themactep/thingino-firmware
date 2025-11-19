WIFI_ATBM_BLE_SITE_METHOD = git
WIFI_ATBM_BLE_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_ATBM_BLE_SITE_BRANCH = master
WIFI_ATBM_BLE_VERSION = 5c4dd2c6febaa924a81551f5ce8d3e71c728cc91

WIFI_ATBM_BLE_LICENSE = GPL-2.0

# Build from ble_thingino subdirectory
WIFI_ATBM_BLE_SUBDIR = ble_thingino

# Pass toolchain to the Makefile
WIFI_ATBM_BLE_MAKE_ENV = \
	CROSS_COMPILE="$(TARGET_CROSS)"

# Build the ble-gatt-server binary
define WIFI_ATBM_BLE_BUILD_CMDS
	$(WIFI_ATBM_BLE_MAKE_ENV) $(MAKE) -C $(@D)/$(WIFI_ATBM_BLE_SUBDIR) all
endef

# Install ble-gatt-server to /usr/sbin and init script to /etc/init.d
define WIFI_ATBM_BLE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/$(WIFI_ATBM_BLE_SUBDIR)/ble-gatt-server $(TARGET_DIR)/usr/sbin/ble-gatt-server
	$(INSTALL) -D -m 0755 $(WIFI_ATBM_BLE_PKGDIR)/files/S59ble-gatt-service $(TARGET_DIR)/etc/init.d/S59ble-gatt-service
endef

$(eval $(generic-package))
