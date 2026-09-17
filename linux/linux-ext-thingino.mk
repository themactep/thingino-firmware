# Thingino linux kernel extension
# Restores binary assets (host tools, firmware blobs) that cannot be
# included in text patches. These are Ingenic-specific files that live
# outside the main cumulative patch.
#
# The big cumulative patch is applied first, then follow-up text patches,
# then this hook restores the assets from a per-kernel-version directory.
# The tree is kept in extracted form under package/linux/files/<version>/,
# mirroring package/all-patches/linux/<version>/ and the u-boot
# package/thingino-uboot/files/<version>/ layout.
#
# Directories are keyed by KERNEL_VERSION (3.10.14, 4.4.94, ...), not
# LINUX_VERSION: for custom-git kernels Buildroot sets LINUX_VERSION to the
# commit hash, which changes on every rebase. A version without a files
# subdirectory has nothing to restore.
#
# The directory test runs inside the recipe because that is when
# BR2_EXTERNAL_THINGINO_PATH is unquoted. Buildroot includes linux/linux.mk
# (and from it, this file) before re-including .br2-external.mk, so a
# parse-time $(wildcard) would see the quoted .config value.

LINUX_THINGINO_BINARY_ASSETS_DIR = \
	$(BR2_EXTERNAL_THINGINO_PATH)/package/linux/files/$(KERNEL_VERSION)

define LINUX_THINGINO_RESTORE_BINARY_ASSETS
	@if [ -d "$(LINUX_THINGINO_BINARY_ASSETS_DIR)" ]; then \
		echo ">>> Thingino: restoring binary assets for Linux $(KERNEL_VERSION)"; \
		cp -a "$(LINUX_THINGINO_BINARY_ASSETS_DIR)/." "$(@D)/"; \
	fi
endef
LINUX_POST_PATCH_HOOKS += LINUX_THINGINO_RESTORE_BINARY_ASSETS
