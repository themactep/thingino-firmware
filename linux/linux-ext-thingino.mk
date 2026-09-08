# Thingino linux kernel extension
# Extracts binary assets (host tools, firmware blobs) that cannot be
# included in text patches. These are Ingenic-specific files that live
# outside the main cumulative patch.
#
# The big cumulative patch is applied first, then follow-up text patches,
# then this hook extracts binary assets from a versioned tarball, if one
# exists for this exact kernel version. Only 3.10.14 (xburst1) has a bundle
# today; xburst2 kernels (T40/T41/...) resolve LINUX_VERSION to a live git
# hash via KERNEL_HASH in thingino.mk, so there is no stable filename to
# ship a bundle under, and none is needed while the kernel source itself
# comes from git rather than a stripped official tarball.
ifneq ($(wildcard $(BR2_EXTERNAL_THINGINO_PATH)/package/linux/thingino-binary-assets-$(LINUX_VERSION).tar.gz),)
define LINUX_EXTRACT_THINGINO_BINARY_ASSETS
	@echo ">>> Thingino: extracting binary assets for Linux $(LINUX_VERSION)"
	$(TAR) -C $(@D) -xzf \
		$(BR2_EXTERNAL_THINGINO_PATH)/package/linux/thingino-binary-assets-$(LINUX_VERSION).tar.gz
endef
LINUX_POST_PATCH_HOOKS += LINUX_EXTRACT_THINGINO_BINARY_ASSETS
endif
