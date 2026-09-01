################################################################################
#
# open-tx-isp
#
################################################################################

OPEN_TX_ISP_SITE_METHOD = git
OPEN_TX_ISP_SITE = https://github.com/opensensor/open-tx-isp
OPEN_TX_ISP_SITE_BRANCH = main
OPEN_TX_ISP_VERSION = 13fd24755114a1b7a2e09dc75236eb08f6185029

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

$(eval $(kernel-module))
$(eval $(generic-package))
