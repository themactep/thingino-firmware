INGENIC_LIB_SITE_METHOD = git
INGENIC_LIB_SITE = https://github.com/gtxaspec/ingenic-lib
INGENIC_LIB_SITE_BRANCH = master
INGENIC_LIB_VERSION = 98b6f0d5b6abf5b91e48c74d398101776c3df5ae
# $(shell git ls-remote $(INGENIC_LIB_SITE) $(INGENIC_LIB_SITE_BRANCH) | head -1 | cut -f1)
INGENIC_LIB_INSTALL_STAGING = YES

INGENIC_LIB_LICENSE = GPL-2.0
INGENIC_LIB_LICENSE_FILES = COPYING

# Determine libc name based on variables
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

# Determine GCC version based on variables
ifeq ($(BR2_THINGINO_INGENIC_SDK_GCC_472),y)
	SDK_LIBC_VERSION := 4.7.2
else ifeq ($(BR2_THINGINO_INGENIC_SDK_GCC_540),y)
	SDK_LIBC_VERSION := 5.4.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_GCC_720),y)
	SDK_LIBC_VERSION := 7.2.0
else
	SDK_LIBC_VERSION := 5.4.0
endif

# Set SDK version based on configuration
ifeq ($(BR2_THINGINO_INGENIC_SDK_A1_1_5_2),y)
	SDK_VERSION := 1.5.2
else ifeq ($(BR2_THINGINO_INGENIC_SDK_A1_1_6_2),y)
	SDK_VERSION := 1.6.2
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T20_3_9_0),y)
	SDK_VERSION := 3.9.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T20_3_12_0),y)
	SDK_VERSION := 3.12.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T21_1_0_33),y)
	SDK_VERSION := 1.0.33
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T23_1_1_0),y)
	SDK_VERSION := 1.1.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T23_1_1_0_MULTI),y)
	SDK_VERSION := 1.1.0-double
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T23_1_1_2),y)
	SDK_VERSION := 1.1.2
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T23_1_1_2_MULTI),y)
	SDK_VERSION := 1.1.2-double
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T30_1_0_5),y)
	SDK_VERSION := 1.0.5
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_1_1),y)
	SDK_VERSION := 1.1.1
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_1_2),y)
	SDK_VERSION := 1.1.2
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_1_4),y)
	SDK_VERSION := 1.1.4
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_1_5),y)
	SDK_VERSION := 1.1.5
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_1_5_2),y)
	SDK_VERSION := 1.1.5.2
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_1_6),y)
	SDK_VERSION := 1.1.6
else ifeq ($(BR2_THINGINO_INGENIC_SDK_C100_2_1_0),y)
	# Use T31 1.1.6 libs for kernel version 3 C100 build
	ifeq ($(KERNEL_VERSION_3),y)
	SDK_VERSION := 1.1.6
	else
	SDK_VERSION := 2.1.0
	endif
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T32_44_1_0_4),y)
	SDK_VERSION := 1.0.4
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T31_1_0_4),y)
	SDK_VERSION := 1.0.4
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T40_1_2_0),y)
	SDK_VERSION := 1.2.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_1_0_1),y)
	SDK_VERSION := 1.0.1
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_44_1_0_1),y)
	SDK_VERSION := 1.0.1
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_1_1_0),y)
	SDK_VERSION := 1.1.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_44_1_1_0),y)
	SDK_VERSION := 1.1.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_1_1_1),y)
	SDK_VERSION := 1.1.1
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_44_1_1_1),y)
	SDK_VERSION := 1.1.1
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_1_2_0),y)
	SDK_VERSION := 1.2.0
else ifeq ($(BR2_THINGINO_INGENIC_SDK_T41_44_1_2_0),y)
	SDK_VERSION := 1.2.0
endif

$(info SDK_VERSION: $(SDK_VERSION))
$(info SDK_LIBC_VERSION: $(SDK_LIBC_VERSION))
$(info SDK_LIBC_NAME: $(SDK_LIBC_NAME))
$(info Building using libs for $(SDK_LIBC_NAME) GCC $(SDK_LIBC_VERSION) toolchain from $(SDK_VERSION) SDK)

ifeq ($(BR2_SOC_FAMILY_INGENIC_T40)$(BR2_SOC_FAMILY_INGENIC_T41)$(BR2_SOC_FAMILY_INGENIC_A1),y)
	# For T40/T41/A1, use their native version regardless of libc type
	LIBALOG_FILE = $(@D)/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
else
	# For all other XBurst1 SoCs
	ifeq ($(SDK_LIBC_NAME),uclibc)
		# With uclibc, use T31 1.1.6 version
		LIBALOG_FILE = $(@D)/T31/lib/1.1.6/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
	else
		# With non-uclibc (including T31 with glibc/musl), use their corresponding libc version
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
