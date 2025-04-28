INGENIC_AUDIODAEMON_SITE_METHOD = git
INGENIC_AUDIODAEMON_SITE = https://github.com/gtxaspec/ingenic_audiodaemon
INGENIC_AUDIODAEMON_SITE_BRANCH = master
INGENIC_AUDIODAEMON_VERSION = eef0e4552f71a4b473c69ebe287baa2cfb732b39
# $(shell git ls-remote $(INGENIC_AUDIODAEMON_SITE) $(INGENIC_AUDIODAEMON_SITE_BRANCH) | head -1 | cut -f1)

INGENIC_AUDIODAEMON_LICENSE = GPL-2.0
INGENIC_AUDIODAEMON_LICENSE_FILES = COPYING

INGENIC_AUDIODAEMON_DEPENDENCIES += cjson libwebsockets ingenic-lib

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	INGENIC_AUDIODAEMON_DEPENDENCIES += ingenic-musl
	GCC_BUILD_TYPE = CONFIG_MUSL_BUILD=y
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	INGENIC_AUDIODAEMON_CFLAGS += -D__UCLIBC__
	GCC_BUILD_TYPE = CONFIG_UCLIBC_BUILD=y
	GCC_BUILD_TYPE += CONFIG_MUSL_BUILD=n
endif

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	INGENIC_AUDIODAEMON_CFLAGS += -D__GLIBC__
	GCC_BUILD_TYPE = CONFIG_GLIBC_BUILD=y
	GCC_BUILD_TYPE += CONFIG_MUSL_BUILD=n
endif

INGENIC_AUDIODAEMON_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

define INGENIC_AUDIODAEMON_BUILD_CMDS
	$(MAKE) version -C $(@D)
	$(MAKE) $(GCC_BUILD_TYPE) CROSS_COMPILE=$(TARGET_CROSS) \
	CFLAGS="$(CFLAGS) $(INGENIC_AUDIODAEMON_CFLAGS) \
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
#$(GCC_BUILD_TYPE)
endef

define INGENIC_AUDIODAEMON_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/config/iad.json \
		$(TARGET_DIR)/etc/iad.json

	$(INSTALL) -D -m 0755 $(INGENIC_AUDIODAEMON_PKGDIR)/files/S96iad \
		$(TARGET_DIR)/etc/init.d/S96iad

	$(INSTALL) -m 0755 -t $(TARGET_DIR)/usr/bin/ \
		$(@D)/build/bin/*

	sed -i '/"AI_attributes": {/,/}/{s/"enabled": true/"enabled": false/}' $(TARGET_DIR)/etc/iad.json
endef

$(eval $(generic-package))
