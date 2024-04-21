PRUDYNT_T_SITE_METHOD = git
PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) HEAD | head -1 | cut -f1)
PRUDYNT_T_DEPENDENCIES = libconfig thingino-live555 thingino-freetype thingino-fonts ingenic-lib ingenic-musl

PRUDYNT_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION_4),y)
PRUDYNT_CFLAGS += -DKERNEL_VERSION_4
endif

PRUDYNT_CFLAGS += \
	-DNO_OPENSSL=1 -Os \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/freetype2 \
	-I$(STAGING_DIR)/usr/include/liveMedia \
	-I$(STAGING_DIR)/usr/include/groupsock \
	-I$(STAGING_DIR)/usr/include/UsageEnvironment \
	-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

PRUDYNT_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

define PRUDYNT_T_BUILD_CMDS
    $(MAKE) \
    	ARCH=$(TARGET_ARCH) \
    	CROSS_COMPILE=$(TARGET_CROSS) \
        CFLAGS="$(PRUDYNT_CFLAGS)" \
        LDFLAGS="$(PRUDYNT_LDFLAGS)" \
        -C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

define PRUDYNT_T_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -D $(@D)/bin/prudynt $(TARGET_DIR)/usr/bin/prudynt
	$(INSTALL) -m 0644 -D $(@D)/prudynt.cfg.example $(TARGET_DIR)/etc/prudynt.cfg
	sed -i 's/;.*$$/;/' $(TARGET_DIR)/etc/prudynt.cfg
	$(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)/files/S95prudynt $(TARGET_DIR)/etc/init.d/S95prudynt
	$(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)/files/S96record $(TARGET_DIR)/etc/init.d/S96record
	$(INSTALL) -m 0755 -D $(@D)/res/thingino_logo_1.bgra $(TARGET_DIR)/usr/share/thingino_logo_1.bgra
	$(INSTALL) -m 0755 -D $(@D)/res/thingino_logo_2.bgra $(TARGET_DIR)/usr/share/thingino_logo_2.bgra
	if echo "$(SOC_RAM)" | grep -q "64"; then \
		sed -i 's/^\([ \t]*\)# *buffers: 2;/\1buffers: 1;/' $(TARGET_DIR)/etc/prudynt.cfg; \
	fi
endef

$(eval $(generic-package))
