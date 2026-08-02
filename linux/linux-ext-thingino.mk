# Thingino linux kernel extension
# Extracts binary assets (host tools, firmware blobs) that cannot be
# included in text patches. These are Ingenic-specific files that live
# outside the main cumulative patch.
#
# The big cumulative patch is applied first (0001-from-3.10.14-to-thingino),
# then follow-up text patches, then this hook extracts binary assets.

ifeq ($(LINUX_VERSION),3.10.14)
define LINUX_EXTRACT_THINGINO_BINARY_ASSETS
	@echo ">>> Thingino: extracting binary assets for Linux $(LINUX_VERSION)"
	$(TAR) -C $(@D) -xzf $(BR2_EXTERNAL_THINGINO_PATH)/package/linux/thingino-binary-assets.tar.gz
endef
LINUX_POST_PATCH_HOOKS += LINUX_EXTRACT_THINGINO_BINARY_ASSETS
endif
