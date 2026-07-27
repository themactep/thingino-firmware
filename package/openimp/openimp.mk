################################################################################
#
# openimp
#
################################################################################

OPENIMP_SITE_METHOD = git
OPENIMP_SITE = https://github.com/opensensor/openimp
OPENIMP_SITE_BRANCH = main
OPENIMP_VERSION = HEAD
# Use HEAD to get the latest version, or specify a commit hash:
# OPENIMP_VERSION = <commit-hash>

OPENIMP_LICENSE = MIT
OPENIMP_LICENSE_FILES = LICENSE

# Install to staging for other packages to link against
OPENIMP_INSTALL_STAGING = YES

# Dependencies - must build after ingenic-sdk and ingenic-lib
OPENIMP_DEPENDENCIES = ingenic-sdk ingenic-lib

# Determine platform based on SOC family
ifeq ($(BR2_SOC_FAMILY_INGENIC_T21),y)
	OPENIMP_PLATFORM = T21
else ifeq ($(BR2_SOC_FAMILY_INGENIC_T23),y)
	OPENIMP_PLATFORM = T23
else ifeq ($(BR2_SOC_FAMILY_INGENIC_T30),y)
	OPENIMP_PLATFORM = T30
else ifeq ($(BR2_SOC_FAMILY_INGENIC_T31),y)
	OPENIMP_PLATFORM = T31
else ifeq ($(BR2_SOC_FAMILY_INGENIC_T40),y)
	OPENIMP_PLATFORM = T40
else ifeq ($(BR2_SOC_FAMILY_INGENIC_T41),y)
	OPENIMP_PLATFORM = T41
else ifeq ($(BR2_SOC_FAMILY_INGENIC_C100),y)
	OPENIMP_PLATFORM = C100
else
	# Default to T31 if platform cannot be determined
	OPENIMP_PLATFORM = T31
endif

# Build commands
define OPENIMP_BUILD_CMDS
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) \
		PLATFORM=$(OPENIMP_PLATFORM) \
		CFLAGS="$(TARGET_CFLAGS) -fPIC -I$(@D)/include" \
		LDFLAGS="$(TARGET_LDFLAGS) -shared -lpthread -lrt" \
		-C $(@D) all
	$(MAKE) CROSS_COMPILE=$(TARGET_CROSS) \
		PLATFORM=$(OPENIMP_PLATFORM) \
		-C $(@D) strip
endef

# Install to staging directory (for other packages to link against)
define OPENIMP_INSTALL_STAGING_CMDS
	$(INSTALL) -d $(STAGING_DIR)/usr/include/imp
	$(INSTALL) -d $(STAGING_DIR)/usr/lib

	$(INSTALL) -m 0644 -t $(STAGING_DIR)/usr/include/imp/ \
		$(@D)/include/imp/*.h

	$(INSTALL) -m 0755 $(@D)/lib/libimp.so \
		$(STAGING_DIR)/usr/lib/libimp.so
	$(INSTALL) -m 0644 $(@D)/lib/libimp.a \
		$(STAGING_DIR)/usr/lib/libimp.a
endef

# Install to target directory - this will OVERRIDE the ingenic-lib libimp.so
define OPENIMP_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/lib

	# Install libimp.so - this OVERRIDES the proprietary version from ingenic-lib
	$(INSTALL) -m 0755 $(@D)/lib/libimp.so \
		$(TARGET_DIR)/usr/lib/libimp.so
endef

# Use a target finalize hook to ensure our library is installed LAST
# This runs after all packages have been installed
define OPENIMP_FINALIZE_TARGET
	@echo "OpenIMP: Ensuring libimp.so override is in place..."
	$(INSTALL) -m 0755 $(BUILD_DIR)/openimp-$(OPENIMP_VERSION)/lib/libimp.so \
		$(TARGET_DIR)/usr/lib/libimp.so
endef
OPENIMP_TARGET_FINALIZE_HOOKS += OPENIMP_FINALIZE_TARGET

$(eval $(generic-package))

