################################################################################
#
# thingino-bluez
#
################################################################################

THINGINO_BLUEZ_VERSION = 5.79
THINGINO_BLUEZ_SOURCE = bluez-$(THINGINO_BLUEZ_VERSION).tar.xz
THINGINO_BLUEZ_SITE = $(BR2_KERNEL_MIRROR)/linux/bluetooth
THINGINO_BLUEZ_LICENSE = MIT
THINGINO_BLUEZ_LICENSE_FILES = LICENSE
THINGINO_BLUEZ_INSTALL_STAGING = YES

THINGINO_BLUEZ_CFLAGS += $(TARGET_CFLAGS) -I$(@D)/lib -I$(@D) -fPIC

define THINGINO_BLUEZ_BUILD_CMDS
	$(MAKE) \
		CC=$(TARGET_CC) \
		LD=$(TARGET_CC) \
		CFLAGS="$(THINGINO_BLUEZ_CFLAGS)" \
		-C $(@D) all
endef

define THINGINO_BLUEZ_COPY_MAKEFILE
	$(INSTALL) -D -m 0644 $(THINGINO_BLUEZ_PKGDIR)/Makefile \
		$(@D)/Makefile
endef

THINGINO_BLUEZ_PRE_CONFIGURE_HOOKS += THINGINO_BLUEZ_COPY_MAKEFILE

define THINGINO_BLUEZ_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libbluetooth.so.3 $(STAGING_DIR)/usr/lib/libbluetooth.so.3
	ln -sf libbluetooth.so.3 $(STAGING_DIR)/usr/lib/libbluetooth.so
	mkdir -p $(STAGING_DIR)/usr/include/bluetooth
	$(INSTALL) -D -m 0644 $(@D)/lib/*.h $(STAGING_DIR)/usr/include/bluetooth/
endef

define THINGINO_BLUEZ_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/libbluetooth.so.3 $(TARGET_DIR)/usr/lib/libbluetooth.so.3
	ln -sf libbluetooth.so.3 $(TARGET_DIR)/usr/lib/libbluetooth.so
endef

$(eval $(generic-package))
