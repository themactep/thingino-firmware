################################################################################
#
# novatek-sensors
#
################################################################################

NOVATEK_SENSORS_VERSION = 88667a5c6f53885a560e72e76a3f94ab0c40372e
NOVATEK_SENSORS_SITE = https://github.com/gtxaspec/novatek-sensors
NOVATEK_SENSORS_SITE_METHOD = git
NOVATEK_SENSORS_LICENSE = GPL-2.0
NOVATEK_SENSORS_DEPENDENCIES = novatek-hdal

NOVATEK_SENSORS_SENSOR = $(call qstrip,$(BR2_SENSOR_1_NAME))

# The driver links against the vendor HDAL modules, which ship no
# Module.symvers: take their CRCs from the modules themselves.
define NOVATEK_SENSORS_HDAL_SYMVERS
	cd $(NOVATEK_HDAL_DIR) && find hdal vos -name '*.ko' | sort | while read ko; do \
		$(TARGET_NM) $$ko | awk -v m="$${ko%.ko}" \
			'/ __crc_/ { sub("__crc_", "", $$3); printf "0x%s\t%s\t%s\tEXPORT_SYMBOL\n", $$1, $$3, m }'; \
	done > $(@D)/hdal.symvers
endef
NOVATEK_SENSORS_PRE_BUILD_HOOKS += NOVATEK_SENSORS_HDAL_SYMVERS

NOVATEK_SENSORS_MODULE_MAKE_OPTS = \
	SENSOR=$(NOVATEK_SENSORS_SENSOR) \
	KBUILD_EXTRA_SYMBOLS=$(@D)/hdal.symvers

$(eval $(kernel-module))
$(eval $(generic-package))
