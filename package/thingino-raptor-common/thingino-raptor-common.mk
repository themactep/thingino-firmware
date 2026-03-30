THINGINO_RAPTOR_COMMON_VERSION = 608ad4ad887d4eb58a2c1f74986e47bda42cc8a1
THINGINO_RAPTOR_COMMON_SITE = https://github.com/gtxaspec/raptor-common
THINGINO_RAPTOR_COMMON_SITE_METHOD = git
THINGINO_RAPTOR_COMMON_INSTALL_STAGING = YES
THINGINO_RAPTOR_COMMON_INSTALL_TARGET = NO

define THINGINO_RAPTOR_COMMON_BUILD_CMDS
	$(MAKE) -C $(@D) CC="$(TARGET_CC)" AR="$(TARGET_AR)"
endef

define THINGINO_RAPTOR_COMMON_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/librss_common.a \
		$(STAGING_DIR)/usr/lib/librss_common.a
	$(INSTALL) -D -m 0644 $(@D)/include/rss_common.h \
		$(STAGING_DIR)/usr/include/rss_common.h
	$(INSTALL) -D -m 0644 $(@D)/include/rss_net.h \
		$(STAGING_DIR)/usr/include/rss_net.h
endef

$(eval $(generic-package))
