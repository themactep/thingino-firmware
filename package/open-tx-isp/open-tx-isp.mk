################################################################################
#
# open-tx-isp
#
################################################################################

OPEN_TX_ISP_SITE_METHOD = git
OPEN_TX_ISP_SITE = https://github.com/opensensor/open-tx-isp
OPEN_TX_ISP_SITE_BRANCH = main
OPEN_TX_ISP_VERSION = e92166b985606613f2395831bac65413c7542877

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

# The T20 driver was written against the pre-refactor ingenic-sdk layout:
# it includes external/ingenic-sdk/{include,3.10.14/isp/t20,3.10.14/sensor-src/
# include}. Thingino's SDK override merged those trees under common/, so
# recreate the old paths as symlinks for the T20 build. Other families are
# self-contained and do not reference external/.
ifeq ($(SOC_FAMILY),t20)
OPEN_TX_ISP_SDK_DIR = $(firstword $(wildcard $(BUILD_DIR)/ingenic-sdk-*))
define OPEN_TX_ISP_T20_COMPAT_TREE
	mkdir -p $(@D)/external/ingenic-sdk/3.10.14/isp \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/include \
		$(@D)/external/ingenic-sdk/include
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/isp/t20 \
		$(@D)/external/ingenic-sdk/3.10.14/isp/t20
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/sensor/include \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src/include
endef
OPEN_TX_ISP_PRE_BUILD_HOOKS += OPEN_TX_ISP_T20_COMPAT_TREE
endif

$(eval $(kernel-module))
$(eval $(generic-package))
