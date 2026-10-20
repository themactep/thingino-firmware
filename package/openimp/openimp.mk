################################################################################
#
# openimp
#
################################################################################

OPENIMP_SITE_METHOD = git
OPENIMP_SITE = https://github.com/Lu-Fi/openimp
OPENIMP_SITE_BRANCH = next
OPENIMP_VERSION = d702887b5cd4b816c9ba3c6c6ce0907ef866c06a

# Upstream describes OpenIMP as MIT but does not currently ship a top-level
# license file for legal-info to collect.
OPENIMP_LICENSE = MIT

OPENIMP_INSTALL_STAGING = YES

OPENIMP_DEPENDENCIES = ingenic-lib
ifeq ($(BR2_PACKAGE_INGENIC_SDK),y)
OPENIMP_DEPENDENCIES += ingenic-sdk
endif

OPENIMP_T31_EXTRA_CFLAGS =
OPENIMP_T31_EXTRA_LIBS =
ifeq ($(BR2_PACKAGE_TINYALSA),y)
ifneq ($(filter t31,$(SOC_FAMILY)),)
ifeq ($(KERNEL_VERSION),7.2.11)
OPENIMP_DEPENDENCIES += tinyalsa
OPENIMP_T31_TINYALSA_STAGING = $(BASE_DIR)/per-package/tinyalsa/host/$(notdir $(patsubst %-,%,$(TARGET_CROSS)))/sysroot
OPENIMP_T31_TINYALSA_INCLUDE = $(BUILD_DIR)/tinyalsa-$(TINYALSA_VERSION)/include
OPENIMP_T31_EXTRA_CFLAGS = -DOPENIMP_T31_ALSA -I$(OPENIMP_T31_TINYALSA_INCLUDE) -I$(OPENIMP_T31_TINYALSA_STAGING)/usr/include
OPENIMP_T31_EXTRA_LIBS = $(OPENIMP_T31_TINYALSA_STAGING)/usr/lib/libtinyalsa.so
endif
endif
endif

OPENIMP_PLATFORM = $(shell echo $(SOC_FAMILY) | tr a-z A-Z)
OPENIMP_PLATFORM_LOWER = $(shell echo $(SOC_FAMILY) | tr A-Z a-z)
OPENIMP_TOOLCHAIN_PREFIX = $(patsubst %-,%,$(TARGET_CROSS))
OPENIMP_OUTPUT_DIR = $(@D)/build/$(OPENIMP_PLATFORM_LOWER)
OPENIMP_BUILT_LIB = $(BUILD_DIR)/openimp-$(OPENIMP_VERSION)/build/$(OPENIMP_PLATFORM_LOWER)/libimp.so

ifneq ($(filter t40 t41,$(SOC_FAMILY)),)
OPENIMP_DEPENDENCIES += thingino-raptor-hal
endif
ifeq ($(SOC_FAMILY),t40)
OPENIMP_T40_HEADERS = $(THINGINO_RAPTOR_HAL_DIR)/ingenic-headers/T40/1.3.1/en
endif
ifeq ($(SOC_FAMILY),t41)
OPENIMP_T41_HEADERS = $(THINGINO_RAPTOR_HAL_DIR)/ingenic-headers/T41/1.2.0/zh
endif

define OPENIMP_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		LC_ALL=C \
		THINGINO_DIR=$(BR2_EXTERNAL_THINGINO_PATH) \
		TOOLCHAIN_PREFIX=$(OPENIMP_TOOLCHAIN_PREFIX) \
		T20_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T20_TARGET_DIR=$(BASE_DIR) \
		T21_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T21_TARGET_DIR=$(BASE_DIR) \
		T23_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T23_TARGET_DIR=$(BASE_DIR) \
		T30_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T30_TARGET_DIR=$(BASE_DIR) \
		T31_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T40_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T40_HEADERS=$(OPENIMP_T40_HEADERS) \
		T41_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T41_HEADERS=$(OPENIMP_T41_HEADERS) \
		T31_EXTRA_CFLAGS="$(OPENIMP_T31_EXTRA_CFLAGS)" \
		T31_EXTRA_LIBS="$(OPENIMP_T31_EXTRA_LIBS)" \
		$(@D)/build-for-device.sh $(OPENIMP_PLATFORM)
endef

ifeq ($(SOC_FAMILY),t23)
# Hybrid T23 build: the OEM libimp.so (installed by ingenic-lib) and the
# Helix worker live under /opt/openimp-t23/, while OpenIMP's libimp.so takes
# /usr/lib/libimp.so for RAD.
define OPENIMP_INSTALL_T23_TARGET
	$(INSTALL) -D -m 0755 $(TARGET_DIR)/usr/lib/libimp.so \
		$(TARGET_DIR)/opt/openimp-t23/libimp.so
	$(INSTALL) -D -m 0755 $(OPENIMP_OUTPUT_DIR)/openimp-t23-helixd \
		$(TARGET_DIR)/opt/openimp-t23/openimp-t23-helixd
endef
endif

define OPENIMP_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(OPENIMP_OUTPUT_DIR)/libimp.so \
		$(STAGING_DIR)/usr/lib/libimp.so
	$(INSTALL) -d $(STAGING_DIR)/usr/include/imp
	$(INSTALL) -d $(STAGING_DIR)/usr/include/openimp
	$(INSTALL) -m 0644 -t $(STAGING_DIR)/usr/include/imp/ \
		$(@D)/include/imp/*.h
	$(INSTALL) -m 0644 -t $(STAGING_DIR)/usr/include/openimp/ \
		$(@D)/include/openimp/*.h
endef

define OPENIMP_INSTALL_TARGET_CMDS
	$(OPENIMP_INSTALL_T23_TARGET)
	$(INSTALL) -D -m 0755 $(OPENIMP_OUTPUT_DIR)/libimp.so \
		$(TARGET_DIR)/usr/lib/libimp.so
	$(INSTALL) -D -m 0755 $(OPENIMP_OUTPUT_DIR)/openimp-tuningd \
		$(TARGET_DIR)/usr/bin/openimp-tuningd
	$(INSTALL) -D -m 0755 $(OPENIMP_PKGDIR)/files/S30openimp-tuning \
		$(TARGET_DIR)/etc/init.d/S30openimp-tuning
	$(INSTALL) -D -m 0644 $(OPENIMP_PKGDIR)/files/openimp-tuning.conf \
		$(TARGET_DIR)/etc/openimp-tuning.conf
endef

define OPENIMP_FINALIZE_TARGET
	$(INSTALL) -D -m 0755 $(OPENIMP_BUILT_LIB) \
		$(TARGET_DIR)/usr/lib/libimp.so
endef
OPENIMP_TARGET_FINALIZE_HOOKS += OPENIMP_FINALIZE_TARGET

$(eval $(generic-package))
