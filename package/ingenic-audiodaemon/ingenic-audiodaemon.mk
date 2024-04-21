INGENIC_AUDIODAEMON_SITE_METHOD = git
INGENIC_AUDIODAEMON_SITE = https://github.com/gtxaspec/ingenic_audiodaemon
INGENIC_AUDIODAEMON_VERSION = $(shell git ls-remote $(INGENIC_AUDIODAEMON_SITE) HEAD | head -1 | cut -f1)

INGENIC_AUDIODAEMON_LICENSE = GPL-2.0
INGENIC_AUDIODAEMON_LICENSE_FILES = COPYING

INGENIC_AUDIODAEMON_DEPENDENCIES += cjson libwebsockets ingenic-musl ingenic-lib

define INGENIC_AUDIODAEMON_BUILD_CMDS
	$(MAKE) version -C $(@D)
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) \
	CFLAGS="$(CFLAGS) \
	-I$(@D)/src/iad/network \
	-I$(@D)/src/iad/audio \
	-I$(@D)/src/iad/client \
	-I$(@D)/src/iad/utils \
	-I$(@D)/include \
	-I$(@D)/build \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/cjson" \
	LDFLAGS="$(LDFLAGS) -L$(STAGING_DIR)/usr/lib -L$(TARGET_DIR)/usr/lib" \
	all -C $(@D)
endef

define INGENIC_AUDIODAEMON_INSTALL_TARGET_CMDS
    cp -a $(@D)/build/bin/. $(TARGET_DIR)/usr/bin/
endef

$(eval $(generic-package))
