PRUDYNT_V3_SITE_METHOD = git
PRUDYNT_V3_SITE = https://github.com/gtxaspec/prudynt-v3
PRUDYNT_V3_VERSION = $(shell git ls-remote $(PRUDYNT_V3_SITE) HEAD | head -1 | cut -f1)
PRUDYNT_V3_DEPENDENCIES = libconfig thingino-live555 ingenic-osdrv-t31 freetype thingino-fonts

# PRUDYNT_CFLAGS = $(TARGET_CLAGS)
PRUDYNT_CFLAGS += -DNO_OPENSSL=1 -Og -g
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/freetype2
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/liveMedia
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/groupsock
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/UsageEnvironment
PRUDYNT_CFLAGS += -I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

PRUDYNT_LDFLAGS = $(TARGET_LDFLAGS)
PRUDYNT_LDFLAGS += -L$(STAGING_DIR)/usr/lib
PRUDYNT_LDFLAGS += -L$(TARGET_DIR)/usr/lib

define PRUDYNT_V3_BUILD_CMDS
    $(MAKE) ARCH=$(TARGET_ARCH) CROSS_COMPILE=$(TARGET_CROSS) \
        CFLAGS="$(PRUDYNT_CFLAGS)" LDFLAGS="$(PRUDYNT_LDFLAGS)" -C $(@D) all
endef

define PRUDYNT_V3_INSTALL_TARGET_CMDS
    $(INSTALL) -m 0755 -D $(@D)/bin/prudynt $(TARGET_DIR)/usr/bin/prudynt
    $(INSTALL) -m 0644 -D $(@D)/prudynt.cfg.example $(TARGET_DIR)/etc/prudynt.cfg
endef

$(eval $(generic-package))
