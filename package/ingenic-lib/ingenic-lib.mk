INGENIC_LIB_SITE_METHOD = git
INGENIC_LIB_SITE = https://github.com/gtxaspec/ingenic-lib
INGENIC_LIB_SITE_BRANCH = master
INGENIC_LIB_VERSION = 98b6f0d5b6abf5b91e48c74d398101776c3df5ae
# $(shell git ls-remote $(INGENIC_LIB_SITE) $(INGENIC_LIB_SITE_BRANCH) | head -1 | cut -f1)
INGENIC_LIB_INSTALL_STAGING = YES

INGENIC_LIB_LICENSE = GPL-2.0
INGENIC_LIB_LICENSE_FILES = COPYING

ifeq ($(BR2_THINGINO_INGENIC_SDK_GCC_GLIBC),y)
	SDK_LIBC_NAME := glibc
else ifeq ($(BR2_THINGINO_INGENIC_SDK_GCC_UCLIBC),y)
	SDK_LIBC_NAME := uclibc
else ifeq ($(BR2_THINGINO_INGENIC_SDK_GCC_MUSL),y)
	SDK_LIBC_NAME := uclibc
else
	# default to uClibc libs
	SDK_LIBC_NAME := uclibc
endif

ifeq ($(BR2_SOC_FAMILY_INGENIC_T40)$(BR2_SOC_FAMILY_INGENIC_T41)$(BR2_SOC_FAMILY_INGENIC_A1),y)
ifeq ($(SDK_LIBC_NAME),uclibc)
	# For T40/T41/A1 with uclibc, use T31 1.1.6 version
	LIBALOG_FILE = $(@D)/T31/lib/1.1.6/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
else
	# For T40/T41/A1 with other libc, use their native version
	LIBALOG_FILE = $(@D)/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
endif
else
ifeq ($(SDK_LIBC_NAME),uclibc)
	# For other XBurst1 SoCs with uclibc, use T31 1.1.6 version
	LIBALOG_FILE = $(@D)/T31/lib/1.1.6/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
else
	# For other XBurst1 SoCs with non-uclibc (including T31 with glibc), use their corresponding libc version
	LIBALOG_FILE = $(@D)/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
endif
endif

define INGENIC_LIB_INSTALL_STAGING_CMDS
	$(INSTALL) -m 0644 -t $(STAGING_DIR)/usr/lib/ \
		$(@D)/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/*.so

	$(INSTALL) -D -m 0644 $(LIBALOG_FILE) \
		$(STAGING_DIR)/usr/lib/libalog.so
endef

define INGENIC_LIB_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/lib/ \
		$(@D)/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/*.so

	$(INSTALL) -D -m 0644 $(LIBALOG_FILE) \
		$(TARGET_DIR)/usr/lib/libalog.so
endef

$(eval $(generic-package))
