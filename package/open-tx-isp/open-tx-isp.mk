################################################################################
#
# open-tx-isp
#
################################################################################

OPEN_TX_ISP_SITE_METHOD = git
OPEN_TX_ISP_SITE = https://github.com/opensensor/open-tx-isp
# Release candidate v2026.11.07-rc3 (728ee0d8); the same tag is published
# on the Lu-Fi/open-tx-isp open-stack fork.
OPEN_TX_ISP_VERSION = v2026.11.07-rc3

# Upstream identifies the project as GPLv3 but does not currently ship a
# top-level license file for legal-info to collect.
OPEN_TX_ISP_LICENSE = GPL-3.0

OPEN_TX_ISP_DEPENDENCIES = ingenic-sdk linux

# Build as out-of-tree kernel module
OPEN_TX_ISP_MODULE_SUBDIRS = driver/$(SOC_FAMILY)

OPEN_TX_ISP_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	DIR=.

# Add XBurst platform include paths for soc headers
OPEN_TX_ISP_MODULE_MAKE_OPTS += \
	EXTRA_CFLAGS="-I$(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/include \
	-I$(LINUX_DIR)/arch/mips/xburst/core/include \
	-I$(LINUX_DIR)/arch/mips/xburst/common/include"

ifeq ($(BR2_PACKAGE_OPENIMP_USE_V4L2),y)
ifeq ($(SOC_FAMILY),t31)
OPEN_TX_ISP_MODULE_MAKE_OPTS += CONFIG_TX_ISP_T31_V4L2=y
else ifeq ($(SOC_FAMILY),t40)
OPEN_TX_ISP_MODULE_MAKE_OPTS += CONFIG_TX_ISP_T40_V4L2=y
else ifeq ($(SOC_FAMILY),t41)
OPEN_TX_ISP_MODULE_MAKE_OPTS += CONFIG_TX_ISP_T41_V4L2=y
endif

ifeq ($(KERNEL_VERSION_3),y)
define OPEN_TX_ISP_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_CAMERA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_DEV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_V4L2)
	$(call KCONFIG_ENABLE_OPT,CONFIG_STAGING)
	$(call KCONFIG_ENABLE_OPT,CONFIG_ANDROID)
	$(call KCONFIG_ENABLE_OPT,CONFIG_ION)
endef
else
define OPEN_TX_ISP_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MEDIA_CAMERA_SUPPORT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_DEV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEO_V4L2)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEOBUF2_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEOBUF2_V4L2)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEOBUF2_MEMOPS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_VIDEOBUF2_DMA_CONTIG)
	$(call KCONFIG_ENABLE_OPT,CONFIG_DMA_SHARED_BUFFER)
endef
endif
endif

# The T10/T20 drivers include the ingenic-sdk headers through
# external/ingenic-sdk/{include,3.10.14/isp/<soc>,3.10.14/sensor-src/include}
# (a git submodule that the buildroot download does not fetch). Point those
# paths at the ingenic-sdk package build. The T10 driver compiles the T20 SDK
# sources against its own headers, so it needs both isp/t10 and isp/t20.
# Both SDK layouts are handled: per-kernel 3.10.14/ trees and the merged
# common/ tree. Other families are self-contained.
ifneq ($(filter t10 t20,$(SOC_FAMILY)),)
OPEN_TX_ISP_SDK_DIR = $(firstword $(wildcard $(BUILD_DIR)/ingenic-sdk-*))
define OPEN_TX_ISP_SDK_COMPAT_TREE
	mkdir -p $(@D)/external/ingenic-sdk/3.10.14/isp \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/include \
		$(@D)/external/ingenic-sdk/include
	if [ -d $(OPEN_TX_ISP_SDK_DIR)/3.10.14/isp ]; then \
		isp=$(OPEN_TX_ISP_SDK_DIR)/3.10.14/isp; \
		sinc=$(OPEN_TX_ISP_SDK_DIR)/3.10.14/sensor-src/include; \
	else \
		isp=$(OPEN_TX_ISP_SDK_DIR)/common/isp; \
		sinc=$(OPEN_TX_ISP_SDK_DIR)/common/sensor/include; \
	fi; \
	ln -sfn $$isp/$(SOC_FAMILY) \
		$(@D)/external/ingenic-sdk/3.10.14/isp/$(SOC_FAMILY) && \
	ln -sfn $$isp/t20 $(@D)/external/ingenic-sdk/3.10.14/isp/t20 && \
	ln -sfn $$sinc $(@D)/external/ingenic-sdk/3.10.14/sensor-src/include
endef
OPEN_TX_ISP_PRE_BUILD_HOOKS += OPEN_TX_ISP_SDK_COMPAT_TREE
endif

$(eval $(kernel-module))
$(eval $(generic-package))
