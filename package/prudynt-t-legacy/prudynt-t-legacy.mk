PRUDYNT_T_LEGACY_SITE_METHOD = git
PRUDYNT_T_LEGACY_SITE = https://github.com/gtxaspec/prudynt-t
PRUDYNT_T_LEGACY_SITE_BRANCH = prudynt-t-old
PRUDYNT_T_LEGACY_VERSION = 57fd23f6b24901d469ce612dd6f75f818f4937fb
# $(shell git ls-remote $(PRUDYNT_T_LEGACY_SITE) $(PRUDYNT_T_LEGACY_SITE_BRANCH) | head -1 | cut -f1)

PRUDYNT_T_LEGACY_GIT_SUBMODULES = YES

PRUDYNT_T_LEGACY_DEPENDENCIES = libconfig thingino-fonts thingino-live555 ingenic-lib thingino-opus faac libhelix-aac
PRUDYNT_T_LEGACY_DEPENDENCIES += thingino-freetype

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
	PRUDYNT_T_LEGACY_DEPENDENCIES += ingenic-musl
endif

ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	PRUDYNT_CFLAGS += -DLIBC_GLIBC
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
	PRUDYNT_CFLAGS += -DLIBC_UCLIBC
endif

PRUDYNT_CFLAGS += -DPLATFORM_$(shell echo $(SOC_FAMILY) | tr a-z A-Z)
ifeq ($(KERNEL_VERSION_4),y)
	PRUDYNT_CFLAGS += -DKERNEL_VERSION_4
endif

# Base compiler flags
PRUDYNT_CFLAGS += \
	-DNO_OPENSSL=1 -Os \
	-I$(STAGING_DIR)/usr/include \
	-I$(STAGING_DIR)/usr/include/liveMedia \
	-I$(STAGING_DIR)/usr/include/groupsock \
	-I$(STAGING_DIR)/usr/include/UsageEnvironment \
	-I$(STAGING_DIR)/usr/include/BasicUsageEnvironment \
	-I$(STAGING_DIR)/usr/include/freetype2

PRUDYNT_LDFLAGS = $(TARGET_LDFLAGS) \
	-L$(STAGING_DIR)/usr/lib \
	-L$(TARGET_DIR)/usr/lib

define PRUDYNT_T_LEGACY_BUILD_CMDS
	$(MAKE) \
		ARCH=$(TARGET_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		CFLAGS="$(PRUDYNT_CFLAGS)" \
		LDFLAGS="$(PRUDYNT_LDFLAGS)" \
		$(if $(filter y,$(BR2_PACKAGE_PRUDYNT_T_LEGACY_DEBUG)),DEBUG=1 DEBUG_STRIP=0,DEBUG_STRIP=1) \
		-C $(@D) all commit_tag=$(shell git show -s --format=%h)
endef

define PRUDYNT_T_LEGACY_INSTALL_TARGET_CMDS
	$(TARGET_CROSS)strip $(@D)/bin/prudynt -o $(TARGET_DIR)/usr/bin/prudynt
	chmod 755 $(TARGET_DIR)/usr/bin/prudynt

	awk -f $(PRUDYNT_T_LEGACY_PKGDIR)/files/device_presets \
		$(PRUDYNT_T_LEGACY_PKGDIR)/files/configs/$(shell awk 'BEGIN {split("$(BR2_CONFIG)", a, "/"); print a[length(a)-1]}') \
		$(@D)/prudynt.cfg.example > $(STAGING_DIR)/prudynt.cfg

	$(INSTALL) -D -m 0644 $(STAGING_DIR)/prudynt.cfg \
		$(TARGET_DIR)/etc/prudynt.cfg

	sed -i 's/;.*$$/;/' $(TARGET_DIR)/etc/prudynt.cfg

	if [ "$(SOC_RAM)" -le "64" ]; then \
		sed -i 's/^\([ \t]*\)# *buffers: 2;/\1buffers: 1;/' $(TARGET_DIR)/etc/prudynt.cfg; \
	fi

	awk '{if(NR>1){gsub(/^[[:space:]]*/,"");if(match($$0,"^[[:space:]]*#")){$$0=""}}}{if(length($$0)){if(NR>1)printf("%s",$$0);else print $$0;}}' \
		$(PRUDYNT_T_LEGACY_PKGDIR)/files/prudyntcfg.awk > $(PRUDYNT_T_LEGACY_PKGDIR)/files/prudyntcfg

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_LEGACY_PKGDIR)/files/prudyntcfg \
		$(TARGET_DIR)/usr/bin/prudyntcfg

	rm $(PRUDYNT_T_LEGACY_PKGDIR)/files/prudyntcfg

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_LEGACY_PKGDIR)/files/S95prudynt \
		$(TARGET_DIR)/etc/init.d/S95prudynt

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_LEGACY_PKGDIR)/files/S96record \
		$(TARGET_DIR)/etc/init.d/S96record

	$(INSTALL) -D -m 0755 $(PRUDYNT_T_LEGACY_PKGDIR)/files/S96vbuffer \
		$(TARGET_DIR)/etc/init.d/S96vbuffer

	$(INSTALL) -D -m 0644 $(@D)/res/thingino_logo_1.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_logo_1.bgra

	$(INSTALL) -D -m 0644 $(@D)/res/thingino_logo_2.bgra \
		$(TARGET_DIR)/usr/share/images/thingino_logo_2.bgra
endef

$(eval $(generic-package))
