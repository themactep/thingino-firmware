################################################################################
#
# openimp
#
################################################################################

OPENIMP_SITE_METHOD = git
OPENIMP_SITE = https://github.com/opensensor/openimp
OPENIMP_SITE_BRANCH = main
OPENIMP_VERSION = 8c60328e4dd002924d53783a9bdbc0a8bc6bb2da

# Upstream describes OpenIMP as MIT but does not currently ship a top-level
# license file for legal-info to collect.
OPENIMP_LICENSE = MIT

OPENIMP_INSTALL_STAGING = YES

OPENIMP_DEPENDENCIES = ingenic-sdk ingenic-lib

OPENIMP_PLATFORM = $(shell echo $(SOC_FAMILY) | tr a-z A-Z)
OPENIMP_PLATFORM_LOWER = $(shell echo $(SOC_FAMILY) | tr A-Z a-z)
OPENIMP_TOOLCHAIN_PREFIX = $(patsubst %-,%,$(TARGET_CROSS))
OPENIMP_OUTPUT_DIR = $(@D)/build/$(OPENIMP_PLATFORM_LOWER)
OPENIMP_BUILT_LIB = $(BUILD_DIR)/openimp-$(OPENIMP_VERSION)/build/$(OPENIMP_PLATFORM_LOWER)/libimp.so

ifeq ($(SOC_FAMILY),t40)
OPENIMP_DEPENDENCIES += thingino-raptor-hal
OPENIMP_T40_HEADERS = $(THINGINO_RAPTOR_HAL_DIR)/ingenic-headers/T40/1.3.1/en
endif

define OPENIMP_BUILD_CMDS
	$(TARGET_MAKE_ENV) \
		THINGINO_DIR=$(BR2_EXTERNAL_THINGINO_PATH) \
		TOOLCHAIN_PREFIX=$(OPENIMP_TOOLCHAIN_PREFIX) \
		T31_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T40_OUTPUT_DIR=$(OPENIMP_OUTPUT_DIR) \
		T40_HEADERS=$(OPENIMP_T40_HEADERS) \
		$(@D)/build-for-device.sh $(OPENIMP_PLATFORM)
endef

define OPENIMP_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0755 $(OPENIMP_OUTPUT_DIR)/libimp.so \
		$(STAGING_DIR)/usr/lib/libimp.so
	$(INSTALL) -d $(STAGING_DIR)/usr/include/imp
	$(INSTALL) -m 0644 -t $(STAGING_DIR)/usr/include/imp/ \
		$(@D)/include/imp/*.h
endef

define OPENIMP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(OPENIMP_OUTPUT_DIR)/libimp.so \
		$(TARGET_DIR)/usr/lib/libimp.so
endef

define OPENIMP_FINALIZE_TARGET
	$(INSTALL) -D -m 0755 $(OPENIMP_BUILT_LIB) \
		$(TARGET_DIR)/usr/lib/libimp.so
endef
OPENIMP_TARGET_FINALIZE_HOOKS += OPENIMP_FINALIZE_TARGET

$(eval $(generic-package))
