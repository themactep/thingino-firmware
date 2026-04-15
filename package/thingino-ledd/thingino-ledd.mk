THINGINO_LEDD_SITE_METHOD = git
THINGINO_LEDD_SITE = https://github.com/themactep/thingino-ledd
THINGINO_LEDD_SITE_BRANCH = master
THINGINO_LEDD_VERSION = d1a37a660cef20bc027f5059594ae2eece510161

define THINGINO_LEDD_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="-Os -ffunction-sections -fdata-sections -flto" \
		LDFLAGS="$(TARGET_LDFLAGS) -Wl,--gc-sections -Wl,-z,norelro -Wl,--as-needed" \
		DEBUGFLAGS="-g0" \
		-C $(@D)
endef

define THINGINO_LEDD_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/ledd \
		$(TARGET_DIR)/usr/bin/ledd
endef

$(eval $(generic-package))
