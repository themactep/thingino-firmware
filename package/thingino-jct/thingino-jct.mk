THINGINO_JCT_SITE_METHOD = git
THINGINO_JCT_SITE = https://github.com/themactep/jct
THINGINO_JCT_SITE_BRANCH = master
THINGINO_JCT_VERSION = 725000f01e497e89785f9a875ab7fe274c996d6c

THINGINO_JCT_LICENSE = MIT
THINGINO_JCT_LICENSE_FILES = LICENSE

# This package provides development files (headers and libraries)
THINGINO_JCT_INSTALL_STAGING = YES

define THINGINO_JCT_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		-C $(@D) lib jct
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

define HOST_THINGINO_JCT_BUILD_CMDS
	$(HOST_MAKE_ENV) $(MAKE) \
		CC="$(HOSTCC)" \
		LD="$(HOSTCC)" \
		AR="$(HOSTAR)" \
		RANLIB="$(HOSTRANLIB)" \
		-C $(@D) lib jct
endef

define HOST_THINGINO_JCT_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/jct $(HOST_DIR)/bin/jct
endef

$(eval $(generic-package))
$(eval $(host-generic-package))
