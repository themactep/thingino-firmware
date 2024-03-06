PRUDYNT_T_SITE_METHOD = git
PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) HEAD | head -1 | cut -f1)
PRUDYNT_T_DEPENDENCIES = libconfig thingino-live555 freetype thingino-fonts

# PRUDYNT_CFLAGS = $(TARGET_CLAGS)
ifeq ($(SOC_FAMILY),t20)
	PRUDYNT_CFLAGS += -DNO_OPENSSL=1 -O0 -DPLATFORM_T20
	PRUDYNT_T_DEPENDENCIES += ingenic-osdrv-t20
else ifeq ($(SOC_FAMILY),t21)
	PRUDYNT_CFLAGS += -DNO_OPENSSL=1 -O0 -DPLATFORM_T21
	PRUDYNT_T_DEPENDENCIES += ingenic-osdrv-t21
else ifeq ($(SOC_FAMILY),t31)
	PRUDYNT_CFLAGS += -DNO_OPENSSL=1 -O2 -DPLATFORM_T31
	PRUDYNT_T_DEPENDENCIES += ingenic-osdrv-t31
endif
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/freetype2
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/liveMedia
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/groupsock
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/UsageEnvironment
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

PRUDYNT_LDFLAGS = $(TARGET_LDFLAGS)
PRUDYNT_LDFLAGS += -L$(STAGING_DIR)/usr/lib
PRUDYNT_LDFLAGS += -L$(TARGET_DIR)/usr/lib

define PRUDYNT_T_BUILD_CMDS
    $(MAKE) ARCH=$(TARGET_ARCH) CROSS_COMPILE=$(TARGET_CROSS) \
        CFLAGS="$(PRUDYNT_CFLAGS)" LDFLAGS="$(PRUDYNT_LDFLAGS)" -C $(@D) all
endef

define PRUDYNT_T_INSTALL_TARGET_CMDS
    $(INSTALL) -m 0755 -D $(@D)/bin/prudynt $(TARGET_DIR)/usr/bin/prudynt
    $(INSTALL) -m 0644 -D $(@D)/prudynt.cfg.example $(TARGET_DIR)/etc/prudynt.cfg
    $(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)files/S95prudynt $(TARGET_DIR)/etc/init.d/S95prudynt
endef

$(eval $(generic-package))
