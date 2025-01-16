INGENIC_AUDIODAEMON_SITE_METHOD = git
INGENIC_AUDIODAEMON_SITE = https://github.com/gtxaspec/ingenic_audiodaemon
INGENIC_AUDIODAEMON_SITE_BRANCH = master
INGENIC_AUDIODAEMON_VERSION = 02edd62d31ab6ecbc8cb2fb4e3850f4a3e10f1d4
# $(shell git ls-remote $(INGENIC_AUDIODAEMON_SITE) $(INGENIC_AUDIODAEMON_SITE_BRANCH) | head -1 | cut -f1)

INGENIC_AUDIODAEMON_LICENSE = GPL-2.0
INGENIC_AUDIODAEMON_LICENSE_FILES = COPYING

INGENIC_AUDIODAEMON_DEPENDENCIES += cjson libwebsockets ingenic-musl ingenic-lib
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	INGENIC_AUDIODAEMON_DEPENDENCIES += ingenic-musl
endif

INGENIC_AUDIODAEMON_LDFLAGS = $(TARGET_LDFLAGS) \
        -L$(STAGING_DIR)/usr/lib \
        -L$(TARGET_DIR)/usr/lib

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
	-I$(STAGING_DIR)/usr/include/cjson \
	-DCONFIG_$(SOC_FAMILY_CAPS)" \
	LDFLAGS="$(INGENIC_AUDIODAEMON_LDFLAGS)" \
	all -C $(@D)
endef

define INGENIC_AUDIODAEMON_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(INGENIC_AUDIODAEMON_PKGDIR)/files/S96iad $(TARGET_DIR)/etc/init.d/S96iad
	$(INSTALL) -m 0755 -D $(@D)/build/bin/* $(TARGET_DIR)/usr/bin/
	$(INSTALL) -m 0644 -D $(@D)/config/iad.json $(TARGET_DIR)/etc/iad.json
	sed -i '/"AI_attributes": {/,/}/{s/"enabled": true/"enabled": false/}' $(TARGET_DIR)/etc/iad.json
endef

$(eval $(generic-package))
