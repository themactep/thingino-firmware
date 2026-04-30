THINGINO_LEDD_SITE_METHOD = git
THINGINO_LEDD_SITE = https://github.com/themactep/thingino-ledd
THINGINO_LEDD_SITE_BRANCH = master
THINGINO_LEDD_VERSION = 4b4b0757f45ff689e8ea046e3ba658ad3b75531a

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
