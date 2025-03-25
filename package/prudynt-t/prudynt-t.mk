PRUDYNT_T_SITE_METHOD = git
ifeq ($(BR2_PACKAGE_PRUDYNT_T_NG),y)
	PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
	PRUDYNT_T_SITE_BRANCH = master
	#PRUDYNT_T_VERSION = 6eab9c0ef6fac8eb80f10ce489bca18295d84729
	PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) $(PRUDYNT_T_SITE_BRANCH) | head -1 | cut -f1)
else
	PRUDYNT_T_SITE = https://github.com/gtxaspec/prudynt-t
	PRUDYNT_T_SITE_BRANCH = prudynt-t-old
	#PRUDYNT_T_VERSION = 5daadef8f84596fd39343a5a794ebfd419c225fb
	PRUDYNT_T_VERSION = $(shell git ls-remote $(PRUDYNT_T_SITE) $(PRUDYNT_T_SITE_BRANCH) | head -1 | cut -f1)
endif

PRUDYNT_T_GIT_SUBMODULES = YES

PRUDYNT_T_DEPENDENCIES = libconfig thingino-live555 thingino-fonts ingenic-lib faac thingino-opus
ifeq ($(BR2_PACKAGE_PRUDYNT_T_NG),y)
	PRUDYNT_T_DEPENDENCIES += libwebsockets libschrift
else
	PRUDYNT_T_DEPENDENCIES += thingino-freetype
endif
ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	PRUDYNT_T_DEPENDENCIES += ingenic-musl
endif

PRUDYNT_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION_4),y)
	PRUDYNT_CFLAGS += -DKERNEL_VERSION_4
endif

PRUDYNT_CFLAGS += \
	-DNO_OPENSSL=1 -Os \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/liveMedia \
	-I$(STAGING_DIR)/usr/include/groupsock \
	-I$(STAGING_DIR)/usr/include/UsageEnvironment \
	-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment

ifneq ($(BR2_PACKAGE_PRUDYNT_T_NG),y)
PRUDYNT_CFLAGS += \
	-I$(STAGING_DIR)/usr/include/freetype2
endif

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
	awk -f $(PRUDYNT_T_PKGDIR)/files/device_presets \
		$(PRUDYNT_T_PKGDIR)/files/configs/$(shell awk 'BEGIN {split("$(BR2_CONFIG)", a, "/"); print a[length(a)-1]}') \
		$(@D)/prudynt.cfg.example > $(STAGING_DIR)/prudynt.cfg
	$(INSTALL) -m 0644 -D $(STAGING_DIR)/prudynt.cfg $(TARGET_DIR)/etc/prudynt.cfg
	sed -i 's/;.*$$/;/' $(TARGET_DIR)/etc/prudynt.cfg
	$(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)/files/S95prudynt $(TARGET_DIR)/etc/init.d/S95prudynt
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/share/images
	$(INSTALL) -m 0644 -D $(@D)/res/thingino_logo_1.bgra $(TARGET_DIR)/usr/share/images/thingino_logo_1.bgra
	$(INSTALL) -m 0644 -D $(@D)/res/thingino_logo_2.bgra $(TARGET_DIR)/usr/share/images/thingino_logo_2.bgra
	if echo "$(SOC_RAM)" | grep -q "64" && ! echo "$(SOC_FAMILY)" | grep -Eq "t23"; then \
		sed -i 's/^\([ \t]*\)# *buffers: 2;/\1buffers: 1;/' $(TARGET_DIR)/etc/prudynt.cfg; \
	fi
	awk '{if(NR>1){gsub(/^[[:space:]]*/,"");if(match($$0,"^[[:space:]]*#")){$$0=""}}}{if(length($$0)){if(NR>1)printf("%s",$$0);else print $$0;}}' \
		$(PRUDYNT_T_PKGDIR)/files/prudyntcfg.awk > $(PRUDYNT_T_PKGDIR)/files/prudyntcfg
	$(INSTALL) -m 0755 -D $(PRUDYNT_T_PKGDIR)/files/prudyntcfg $(TARGET_DIR)/usr/bin/prudyntcfg
	rm $(PRUDYNT_T_PKGDIR)/files/prudyntcfg
#	if [ "$(BR2_PACKAGE_PRUDYNT_T_NG)" = "y" ]; then \
#	echo "Removing LD_PRELOAD command line from init script"; \
#	sed -i '/^COMMAND=/d' $(TARGET_DIR)/etc/init.d/S95prudynt; \
#	fi
endef

$(eval $(generic-package))
