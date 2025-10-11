THINGINO_JCT_SITE_METHOD = git
THINGINO_JCT_SITE = https://github.com/themactep/jct
THINGINO_JCT_SITE_BRANCH = master
THINGINO_JCT_VERSION = 061376cec5e1347d8d52875443939ba3497f9966

THINGINO_JCT_LICENSE = MIT
THINGINO_JCT_LICENSE_FILES = LICENSE

# This package provides development files (headers and libraries)
THINGINO_JCT_INSTALL_STAGING = YES

define THINGINO_JCT_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) LDFLAGS="$(TARGET_LDFLAGS)" -C $(@D) lib jct
endef

define THINGINO_JCT_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libjct.a \
		$(STAGING_DIR)/usr/lib/libjct.a
	$(INSTALL) -D -m 0755 $(@D)/libjct.so \
		$(STAGING_DIR)/usr/lib/libjct.so.1.0.0
	$(INSTALL) -D -m 0644 $(@D)/src/json_config.h \
		$(STAGING_DIR)/usr/include/json_config.h
	ln -sf libjct.so.1.0.0 $(STAGING_DIR)/usr/lib/libjct.so.1
	ln -sf libjct.so.1.0.0 $(STAGING_DIR)/usr/lib/libjct.so
endef

define THINGINO_JCT_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/jct \
		$(TARGET_DIR)/usr/bin/jct
	$(INSTALL) -D -m 0755 $(@D)/libjct.so \
		$(TARGET_DIR)/usr/lib/libjct.so.1.0.0
	$(INSTALL) -D -m 0644 $(@D)/libjct.a \
		$(TARGET_DIR)/usr/lib/libjct.a
	$(INSTALL) -D -m 0644 $(@D)/src/json_config.h \
		$(TARGET_DIR)/usr/include/json_config.h
	ln -sf libjct.so.1.0.0 $(TARGET_DIR)/usr/lib/libjct.so.1
	ln -sf libjct.so.1.0.0 $(TARGET_DIR)/usr/lib/libjct.so
endef

$(eval $(generic-package))
