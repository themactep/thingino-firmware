PRUDYNT_V3_SITE_METHOD = git
PRUDYNT_V3_SITE = https://github.com/gtxaspec/prudynt-v3
PRUDYNT_V3_VERSION = $(shell git ls-remote $(PRUDYNT_V3_SITE) HEAD | head -1 | cut -f1)
PRUDYNT_V3_DEPENDENCIES = libconfig thingino-live555 ingenic-osdrv-t31 freetype

define PRUDYNT_V3_BUILD_CMDS
    $(MAKE) ARCH=$(TARGET_ARCH) CROSS_COMPILE=$(TARGET_CROSS) \
        CFLAGS="-DNO_OPENSSL=1 -Og -g \
		-I$(STAGING_DIR)/usr/include \
		-I$(STAGING_DIR)/usr/include/freetype2 \
		-I$(STAGING_DIR)/usr/include/liveMedia \
		-I$(STAGING_DIR)/usr/include/groupsock \
		-I$(STAGING_DIR)/usr/include/UsageEnvironment \
		-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment" \
        LDFLAGS="$(TARGET_LDFLAGS) \
        	-L$(STAGING_DIR)/usr/lib \
        	-L$(TARGET_DIR)/usr/lib" \
        -C $(@D) \
        all
endef

define PRUDYNT_V3_INSTALL_TARGET_CMDS
    $(INSTALL) -m 0755 -D $(@D)/bin/prudynt $(TARGET_DIR)/usr/bin/prudynt
endef

$(eval $(generic-package))
