# Thingino linux kernel extension
# Applies the per-SoC 4.4.94 kernel patch and restores binary assets (host
# tools, firmware blobs) that cannot be included in text patches. These are
# Ingenic-specific files that live outside the cumulative/common patch.
#
# 3.10.14 ships one cumulative text patch plus a flat binary-asset tree
# under package/linux/files/3.10.14/. 4.4.94 ships a common text patch under
# package/all-patches/linux/4.4.94/ (applied with 0002/0003 by the global
# patch dir) plus a per-SoC text patch and per-SoC binary assets, both keyed
# by KERNEL_SOC.
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
LINUX_THINGINO_SOC_PATCH_DIR = \
	$(BR2_EXTERNAL_THINGINO_PATH)/package/all-patches/linux/$(KERNEL_VERSION)/soc/$(KERNEL_SOC)

# 4.4.94: the common patch lands via BR2_GLOBAL_PATCH_DIR; the SoC patch is
# applied here. Prepending to LINUX_POST_PATCH_HOOKS makes it run before
# LINUX_APPLY_LOCAL_PATCHES, so a camera's own kernel patches
# (BR2_LINUX_KERNEL_PATCH) apply on top of the SoC tree they were written for.
ifneq ($(KERNEL_SOC),)
define LINUX_THINGINO_APPLY_SOC_PATCH
	@if [ -d "$(LINUX_THINGINO_SOC_PATCH_DIR)" ]; then \
		echo ">>> Thingino: applying $(KERNEL_SOC) kernel patch"; \
		$(APPLY_PATCHES) $(@D) "$(LINUX_THINGINO_SOC_PATCH_DIR)" \*.patch; \
	fi
endef
LINUX_POST_PATCH_HOOKS := LINUX_THINGINO_APPLY_SOC_PATCH $(LINUX_POST_PATCH_HOOKS)
endif

define LINUX_THINGINO_RESTORE_BINARY_ASSETS
	@if [ -d "$(LINUX_THINGINO_BINARY_ASSETS_DIR)/common" ]; then \
		echo ">>> Thingino: restoring $(KERNEL_VERSION) binary assets"; \
		cp -a "$(LINUX_THINGINO_BINARY_ASSETS_DIR)/common/." "$(@D)/"; \
		if [ -n "$(KERNEL_SOC)" ] && [ -d "$(LINUX_THINGINO_BINARY_ASSETS_DIR)/$(KERNEL_SOC)" ]; then \
			cp -a "$(LINUX_THINGINO_BINARY_ASSETS_DIR)/$(KERNEL_SOC)/." "$(@D)/"; \
		fi; \
	elif [ -d "$(LINUX_THINGINO_BINARY_ASSETS_DIR)" ]; then \
		echo ">>> Thingino: restoring binary assets for Linux $(KERNEL_VERSION)"; \
		cp -a "$(LINUX_THINGINO_BINARY_ASSETS_DIR)/." "$(@D)/"; \
	fi
endef
LINUX_POST_PATCH_HOOKS += LINUX_THINGINO_RESTORE_BINARY_ASSETS
