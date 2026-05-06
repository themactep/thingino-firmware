INGENIC_LIB_SITE_METHOD = git
INGENIC_LIB_SITE = https://github.com/gtxaspec/ingenic-lib
INGENIC_LIB_SITE_BRANCH = master
INGENIC_LIB_VERSION = 9bfe42f4a20c65eefd33c509abfa38e383b4119f
INGENIC_LIB_INSTALL_STAGING = YES

INGENIC_LIB_LICENSE = GPL-2.0
INGENIC_LIB_LICENSE_FILES = COPYING

# Determine libc name based on variables
ifeq ($(BR2_TOOLCHAIN_USES_GLIBC),y)
	SDK_LIBC_NAME := glibc
else
	SDK_LIBC_NAME := uclibc
endif

# Determine GCC version based on variables
ifneq ($(filter t10 t20 t21 t30,$(SOC_FAMILY)),)
	SDK_LIBC_VERSION := 4.7.2
else ifneq ($(filter t40 t41 a1,$(SOC_FAMILY)),)
	SDK_LIBC_VERSION := 7.2.0
else
	SDK_LIBC_VERSION := 5.4.0
endif

# Set SDK version based on configuration
ifeq ($(SOC_FAMILY),a1)
	SDK_VERSION := 1.7.0
else ifeq ($(SOC_FAMILY),c100)
	ifeq ($(KERNEL_VERSION),3.10.14)
		SDK_VERSION := 1.1.6
	else
		SDK_VERSION := 2.1.0
	endif
else ifeq ($(SOC_FAMILY),t10)
	SDK_VERSION := 3.12.0
else ifeq ($(SOC_FAMILY),t20)
	SDK_VERSION := 3.12.0
else ifeq ($(SOC_FAMILY),t21)
	SDK_VERSION := 1.0.33
else ifeq ($(SOC_FAMILY),t23)
	SDK_VERSION := 1.3.0
else ifeq ($(SOC_FAMILY),t30)
	SDK_VERSION := 1.0.5
else ifeq ($(SOC_FAMILY),t31)
	ifeq ($(KERNEL_VERSION),4.4.94)
		SDK_VERSION := 1.1.5.2
	else
		SDK_VERSION := 1.1.6
	endif
else ifeq ($(SOC_FAMILY),t32)
	SDK_VERSION := 1.0.6
else ifeq ($(SOC_FAMILY),t40)
	SDK_VERSION := 1.3.1
else ifeq ($(SOC_FAMILY),t41)
	SDK_VERSION := 1.2.6
endif

SDK_LIB_DIR = $(@D)/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)

ifneq ($(filter t40 t41 a1,$(SOC_FAMILY)),)
	LIBALOG_FILE = $(SDK_LIB_DIR)/libalog.so
else
	ifeq ($(SDK_LIBC_NAME),uclibc)
		LIBALOG_FILE = $(@D)/T31/lib/1.1.6/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
	else
		LIBALOG_FILE = $(SDK_LIB_DIR)/libalog.so
	endif
endif

ACCEL_DIR = $(@D)/acceleration-modules

# Staging: install core libs for linking (skip libsysutils on a1)
define INGENIC_LIB_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(SDK_LIB_DIR)/libimp.so \
		$(STAGING_DIR)/usr/lib/libimp.so
	$(INSTALL) -D -m 0644 $(LIBALOG_FILE) \
		$(STAGING_DIR)/usr/lib/libalog.so
	$(if $(filter-out a1,$(SOC_FAMILY)),\
		$(INSTALL) -D -m 0644 $(SDK_LIB_DIR)/libsysutils.so \
			$(STAGING_DIR)/usr/lib/libsysutils.so \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_AUDIOPROCESS),\
		$(INSTALL) -D -m 0644 $(SDK_LIB_DIR)/libaudioProcess.so \
			$(STAGING_DIR)/usr/lib/libaudioProcess.so \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_JZDL),\
		$(INSTALL) -D -m 0644 \
			$(ACCEL_DIR)/jzdl/lib/$(SDK_LIBC_VERSION)/$(SDK_LIBC_NAME)/libjzdl.m.so \
			$(STAGING_DIR)/usr/lib/ \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_PERSONDET),\
		$(INSTALL) -m 0644 -t $(STAGING_DIR)/usr/lib/ \
			$(ACCEL_DIR)/ivs/lib/$(SDK_LIBC_VERSION)/IVS/$(SDK_LIBC_NAME)/libpersonDet_inf.so \
			$(ACCEL_DIR)/ivs/lib/$(SDK_LIBC_VERSION)/IVS/$(SDK_LIBC_NAME)/libjzdl.so \
	)
endef

# Target: only install what's selected
define INGENIC_LIB_INSTALL_TARGET_CMDS
	$(if $(BR2_PACKAGE_INGENIC_LIB_LIBIMP),\
		$(INSTALL) -D -m 0644 $(SDK_LIB_DIR)/libimp.so \
			$(TARGET_DIR)/usr/lib/libimp.so \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_LIBALOG),\
		$(INSTALL) -D -m 0644 $(LIBALOG_FILE) \
			$(TARGET_DIR)/usr/lib/libalog.so \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_LIBSYSUTILS),\
		$(if $(filter-out a1,$(SOC_FAMILY)),\
		$(INSTALL) -D -m 0644 $(SDK_LIB_DIR)/libsysutils.so \
			$(TARGET_DIR)/usr/lib/libsysutils.so \
		) \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_AUDIOPROCESS),\
		$(INSTALL) -D -m 0644 $(SDK_LIB_DIR)/libaudioProcess.so \
			$(TARGET_DIR)/usr/lib/libaudioProcess.so \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_JZDL),\
		$(INSTALL) -D -m 0644 \
			$(ACCEL_DIR)/jzdl/lib/$(SDK_LIBC_VERSION)/$(SDK_LIBC_NAME)/libjzdl.m.so \
			$(TARGET_DIR)/usr/lib/ \
	)
	$(if $(BR2_PACKAGE_INGENIC_LIB_PERSONDET),\
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/lib/ \
			$(ACCEL_DIR)/ivs/lib/$(SDK_LIBC_VERSION)/IVS/$(SDK_LIBC_NAME)/libpersonDet_inf.so \
			$(ACCEL_DIR)/ivs/lib/$(SDK_LIBC_VERSION)/IVS/$(SDK_LIBC_NAME)/libjzdl.so \
	)
endef

$(eval $(generic-package))
