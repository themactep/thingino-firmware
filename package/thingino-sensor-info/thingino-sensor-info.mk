THINGINO_SENSOR_INFO_VERSION = a432193bb8181973c754367e57da33f4f9752014
THINGINO_SENSOR_INFO_SITE = $(call github,thingino,sensor-info,$(THINGINO_SENSOR_INFO_VERSION))

THINGINO_SENSOR_INFO_LICENSE = GPL-2.0
THINGINO_SENSOR_INFO_LICENSE_FILES = LICENSE

# The repo's standalone default is a static binary; inside the firmware
# link dynamically against the system libc to keep the image small.
define THINGINO_SENSOR_INFO_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="$(TARGET_CFLAGS) -std=gnu99" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		-C $(@D) sinfo
endef

define THINGINO_SENSOR_INFO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/sinfo $(TARGET_DIR)/usr/sbin/sinfo
	ln -sf sinfo $(TARGET_DIR)/usr/sbin/sensor-info
endef

$(eval $(generic-package))
