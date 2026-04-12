THINGINO_RAPTOR_COMMON_VERSION = 56067b3
THINGINO_RAPTOR_COMMON_SITE = https://github.com/gtxaspec/raptor-common
THINGINO_RAPTOR_COMMON_SITE_METHOD = git
THINGINO_RAPTOR_COMMON_INSTALL_STAGING = YES
THINGINO_RAPTOR_COMMON_INSTALL_TARGET = YES

define THINGINO_RAPTOR_COMMON_BUILD_CMDS
	$(MAKE) -C $(@D) CC="$(TARGET_CC)"
endef

define THINGINO_RAPTOR_COMMON_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(@D)/librss_common.so \
		$(STAGING_DIR)/usr/lib/librss_common.so
	for h in rss_common.h rss_net.h rss_http.h rss_tls.h cJSON.h; do \
		$(INSTALL) -D -m 0644 $(@D)/include/$$h \
			$(STAGING_DIR)/usr/include/$$h; \
	done
	$(INSTALL) -D -m 0644 $(@D)/src/rss_tls.c \
		$(STAGING_DIR)/usr/share/raptor-common/rss_tls.c
endef

define THINGINO_RAPTOR_COMMON_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/librss_common.so \
		$(TARGET_DIR)/usr/lib/librss_common.so
endef

$(eval $(generic-package))
