PRUDYNT_T_SITE_METHOD = git
PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) HEAD | head -1 | cut -f1)
PRUDYNT_T_DEPENDENCIES = libconfig thingino-live555 thingino-freetype thingino-fonts

ifeq ($(SOC_FAMILY),t20)
	PRUDYNT_CFLAGS += -DPLATFORM_T20
	PRUDYNT_T_DEPENDENCIES += ingenic-osdrv-t20
else ifeq ($(SOC_FAMILY),t21)
	PRUDYNT_CFLAGS += -DPLATFORM_T21
	PRUDYNT_T_DEPENDENCIES += ingenic-osdrv-t21
else ifeq ($(SOC_FAMILY),t31)
	PRUDYNT_CFLAGS += -DPLATFORM_T31
	PRUDYNT_T_DEPENDENCIES += ingenic-osdrv-t31
endif

PRUDYNT_CFLAGS += \
	-DNO_OPENSSL=1 -O2 \
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
    $(MAKE) ARCH=$(TARGET_ARCH) CROSS_COMPILE=$(TARGET_CROSS) \
        CFLAGS="$(PRUDYNT_CFLAGS)" LDFLAGS="$(PRUDYNT_LDFLAGS)" -C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

SENSOR_I2C_ADDRESS = $(shell awk '/address:/ {print $$2}' $(TARGET_DIR)/etc/sensor/$(SENSOR_MODEL).yaml)
SENSOR_FPS = $(shell awk '/#define SENSOR_OUTPUT_MAX_FPS/ {print $$3}' $(OUTPUT_DIR)/build/ingenic-opensdk/kernel/sensors/$(SOC_FAMILY)/$(SENSOR_MODEL).c)

define PRUDYNT_T_INSTALL_TARGET_CMDS
    $(INSTALL) -m 0755 -D $(@D)/bin/prudynt $(TARGET_DIR)/usr/bin/prudynt
    $(INSTALL) -m 0644 -D $(@D)/prudynt.cfg.example $(TARGET_DIR)/etc/prudynt.cfg
    $(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)files/S95prudynt $(TARGET_DIR)/etc/init.d/S95prudynt
    sed -i '/i2c_address:/ s/0x37/$(SENSOR_I2C_ADDRESS)/' $(TARGET_DIR)/etc/prudynt.cfg
    sed -i '/model:/ s/"gc2053"/$(BR2_SENSOR_MODEL)/' $(TARGET_DIR)/etc/prudynt.cfg
    sed -i '/fps:/ s/24/$(SENSOR_FPS)/' $(TARGET_DIR)/etc/prudynt.cfg
endef

$(eval $(generic-package))
