PRUDYNT_T_SITE_METHOD = git
PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) HEAD | head -1 | cut -f1)
PRUDYNT_T_DEPENDENCIES = libconfig thingino-live555 ingenic-sdk thingino-freetype thingino-fonts

PRUDYNT_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
PRUDYNT_T_DEPENDENCIES += ingenic-sdk

PRUDYNT_CFLAGS += \
	-DNO_OPENSSL=1 -Os \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/freetype2 \
	-I$(STAGING_DIR)/usr/include/liveMedia \
	-I$(STAGING_DIR)/usr/include/groupsock \
	-I$(STAGING_DIR)/usr/include/UsageEnvironment \
	-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

PRUDYNT_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

define PRUDYNT_T_BUILD_CMDS
    $(MAKE) \
    	ARCH=$(TARGET_ARCH) \
    	CROSS_COMPILE=$(TARGET_CROSS) \
        CFLAGS="$(PRUDYNT_CFLAGS)" \
        LDFLAGS="$(PRUDYNT_LDFLAGS)" \
        -C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

SENSOR_I2C_ADDRESS = $(shell awk '/address:/ {print $$2}' $(TARGET_DIR)/etc/sensor/$(SENSOR_MODEL).yaml)

## TODO: this should be done better
# SENSOR_FPS=$$(awk '/#define SENSOR_OUTPUT_MAX_FPS/ function nvl(x) {return x==""?"30":x} {print nvl($$3)}' $$(OUTPUT_DIR)/build/ingenic-sdk-*/sensor-src/$(SOC_FAMILY)/$(SENSOR_MODEL).c)
# sed -i '/fps:/ s/24/$(SENSOR_FPS)/' $(TARGET_DIR)/etc/prudynt.cfg

define PRUDYNT_T_INSTALL_TARGET_CMDS
    $(INSTALL) -m 0755 -D $(@D)/bin/prudynt $(TARGET_DIR)/usr/bin/prudynt
    $(INSTALL) -m 0644 -D $(@D)/prudynt.cfg.example $(TARGET_DIR)/etc/prudynt.cfg
    $(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)files/S95prudynt $(TARGET_DIR)/etc/init.d/S95prudynt
    $(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)files/S96record $(TARGET_DIR)/etc/init.d/S96record
    $(INSTALL) -m 0755 -D $(@D)/res/thingino_logo_1.bgra $(TARGET_DIR)/usr/share/thingino_logo_1.bgra
    sed -i '/i2c_address:/ s/0x37/$(SENSOR_I2C_ADDRESS)/' $(TARGET_DIR)/etc/prudynt.cfg
    sed -i '/model:/ s/"gc2053"/$(BR2_SENSOR_MODEL)/' $(TARGET_DIR)/etc/prudynt.cfg
endef

$(eval $(generic-package))
