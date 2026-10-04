################################################################################
#
# openimp
#
################################################################################

OPENIMP_SITE_METHOD = git
OPENIMP_SITE = https://github.com/Lu-Fi/openimp
# Release tag of the Lu-Fi open-stack fork. The tag is cut after the soak
# of its candidate, 0c02f45a7886832e7351e32f9f08954142858d06.
OPENIMP_VERSION = v2026.10.05

# Upstream describes OpenIMP as MIT but does not currently ship a top-level
# license file for legal-info to collect.
OPENIMP_LICENSE = MIT

OPENIMP_INSTALL_STAGING = YES

OPENIMP_DEPENDENCIES = ingenic-sdk ingenic-lib

OPENIMP_PLATFORM = $(shell echo $(SOC_FAMILY) | tr a-z A-Z)
OPENIMP_PLATFORM_LOWER = $(shell echo $(SOC_FAMILY) | tr A-Z a-z)

# T10 shares the T20 userspace and SDK; build it with the T20 platform.
ifeq ($(SOC_FAMILY),t10)
OPENIMP_PLATFORM = T20
OPENIMP_PLATFORM_LOWER = t20
endif
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
		$(@D)/build-for-device.sh $(OPENIMP_PLATFORM)
endef

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
