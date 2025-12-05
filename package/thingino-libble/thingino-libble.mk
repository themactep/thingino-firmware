################################################################################
#
# thingino-libble
#
################################################################################

THINGINO_LIBBLE_VERSION = v0.0.4
THINGINO_LIBBLE_SITE = https://github.com/yinzara/libblepp
THINGINO_LIBBLE_SITE_METHOD = git
THINGINO_LIBBLE_SITE_BRANCH = main
THINGINO_LIBBLE_LICENSE = MIT
THINGINO_LIBBLE_LICENSE_FILES = LICENSE
THINGINO_LIBBLE_INSTALL_STAGING = YES

# Conditional dependency: use NimBLE for ATBM WiFi chips with BLE, otherwise BlueZ
ifneq ($(BR2_PACKAGE_WIFI_ATBM6012BX)$(BR2_PACKAGE_WIFI_ATBM6031X)$(BR2_PACKAGE_WIFI_ATBM6032X),)
# At least one ATBM WiFi chip with BLE is selected
THINGINO_LIBBLE_DEPENDENCIES = thingino-nimble
else
# No ATBM WiFi chip selected, use BlueZ
THINGINO_LIBBLE_DEPENDENCIES = thingino-bluez
endif

THINGINO_LIBBLE_CFLAGS += \
    $(TARGET_CFLAGS) \
    -I$(@D) \
	-I$(STAGING_DIR)/usr/include \
	-fPIC

THINGINO_LIBBLE_CXXFLAGS += \
    $(TARGET_CXXFLAGS) \
    -I$(@D) \
	-I$(STAGING_DIR)/usr/include \
	-fPIC

ifneq ($(BR2_PACKAGE_WIFI_ATBM6012BX)$(BR2_PACKAGE_WIFI_ATBM6031X)$(BR2_PACKAGE_WIFI_ATBM6032X),)
THINGINO_LIBBLE_CXXFLAGS += -DBLEPP_NIMBLE_SUPPORT -DBLEPP_SERVER_SUPPORT -DCONFIG_LINUX_BLE_STACK_APP=1
else
THINGINO_LIBBLE_CXXFLAGS += -DBLEPP_BLUEZ_SUPPORT -DBLEPP_SERVER_SUPPORT
endif

THINGINO_LIBBLE_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib \
	-lstdc++

ifneq ($(BR2_PACKAGE_WIFI_ATBM6012BX)$(BR2_PACKAGE_WIFI_ATBM6031X)$(BR2_PACKAGE_WIFI_ATBM6032X),)
define THINGINO_LIBBLE_CONFIGURE_CMDS
	(cd $(@D) ; ./configure --with-server-support \
				--with-nimble-support \
				--without-bluez-support \
				NIMBLE_LIBDIR=$(STAGING_DIR)/usr/lib \
				CFLAGS="$(THINGINO_LIBBLE_CFLAGS)" \
				CXXFLAGS="$(THINGINO_LIBBLE_CXXFLAGS)" \
				LDFLAGS="$(THINGINO_LIBBLE_LDFLAGS)" )
endef
else
define THINGINO_LIBBLE_CONFIGURE_CMDS
	(cd $(@D) ; ./configure --with-server-support \
				--with-bluez-support \
				CFLAGS="$(THINGINO_LIBBLE_CFLAGS)" \
				CXXFLAGS="$(THINGINO_LIBBLE_CXXFLAGS)" \
				LDFLAGS="$(THINGINO_LIBBLE_LDFLAGS)" )
endef
endif

ifneq ($(BR2_PACKAGE_WIFI_ATBM6012BX)$(BR2_PACKAGE_WIFI_ATBM6031X)$(BR2_PACKAGE_WIFI_ATBM6032X),)
define THINGINO_LIBBLE_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CC=$(TARGET_CC) \
		CXX=$(TARGET_CXX) \
		LD=$(TARGET_CXX) \
		BLEPP_NIMBLE_SUPPORT=1 \
		BLEPP_SERVER_SUPPORT=1 \
		NIMBLE_LIBDIR=$(STAGING_DIR)/usr/lib \
		CFLAGS="$(THINGINO_LIBBLE_CFLAGS)" \
		CXXFLAGS="$(THINGINO_LIBBLE_CXXFLAGS)" \
		LDFLAGS="$(THINGINO_LIBBLE_LDFLAGS)" \
		-C $(@D) lib
endef
else
define THINGINO_LIBBLE_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CC=$(TARGET_CC) \
		CXX=$(TARGET_CXX) \
		LD=$(TARGET_CXX) \
		BLEPP_BLUEZ_SUPPORT=1 \
		BLEPP_SERVER_SUPPORT=1 \
		CFLAGS="$(THINGINO_LIBBLE_CFLAGS)" \
		CXXFLAGS="$(THINGINO_LIBBLE_CXXFLAGS)" \
		LDFLAGS="$(THINGINO_LIBBLE_LDFLAGS)" \
		-C $(@D) lib
endef
endif

define THINGINO_LIBBLE_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libble++.so.0.5 $(STAGING_DIR)/usr/lib/libble++.so.0.5
	ln -sf libble++.so.0.5 $(STAGING_DIR)/usr/lib/libble++.so
	$(INSTALL) -D -m 0644 $(@D)/libble++.a $(STAGING_DIR)/usr/lib/libble++.a
	mkdir -p $(STAGING_DIR)/usr/include/blepp
	$(INSTALL) -D -m 0644 $(@D)/blepp/*.h $(STAGING_DIR)/usr/include/blepp/
endef

define THINGINO_LIBBLE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libble++.so.0.5 $(TARGET_DIR)/usr/lib/libble++.so.0.5
	ln -sf libble++.so.0.5 $(TARGET_DIR)/usr/lib/libble++.so
endef

$(eval $(generic-package))
