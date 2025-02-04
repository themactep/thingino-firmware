THINGINO_LEDD_SITE_METHOD = git
THINGINO_LEDD_SITE = https://github.com/gtxaspec/thingino-ledd
THINGINO_LEDD_SITE_BRANCH = master
THINGINO_LEDD_VERSION = 2d11db5f06927f05ffd3bb932be688f4b8e7e198
# $(shell git ls-remote $(THINGINO_LEDD_SITE) $(THINGINO_LEDD_SITE_BRANCH) | head -1 | cut -f1)

define THINGINO_LEDD_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) \
	    CFLAGS="-Os -ffunction-sections -fdata-sections -flto" \
	    LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -Wl,-z,norelro -Wl,--as-needed" \
	    DEBUGFLAGS="-g0" \
	    -C $(@D)
endef

define THINGINO_LEDD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ledd $(TARGET_DIR)/usr/bin/ledd
endef

$(eval $(generic-package))
