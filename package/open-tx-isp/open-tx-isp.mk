################################################################################
#
# open-tx-isp
#
################################################################################

OPEN_TX_ISP_SITE_METHOD = git
OPEN_TX_ISP_SITE = https://github.com/Lu-Fi/open-tx-isp
# Release tag of the Lu-Fi open-stack fork. The tag is cut after the soak
# of its candidate, 40cc77eccb959d265b307b7517eff9eb97552a7f.
OPEN_TX_ISP_VERSION = v2026.10.05

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

# The T20/T10 drivers were written against the pre-refactor ingenic-sdk
# layout: they include external/ingenic-sdk/{include,3.10.14/isp/<soc>,
# 3.10.14/sensor-src/include}. Thingino's SDK override merged those trees under
# common/, so recreate the old paths as symlinks. The T10 driver is a thin
# wrapper over the T20 SDK sources (driver/t20/sdk) but compiles them against
# its own headers, so it needs both isp/t10 and isp/t20. Other families are
# self-contained and do not reference external/.
ifneq ($(filter t10 t20,$(SOC_FAMILY)),)
OPEN_TX_ISP_SDK_DIR = $(firstword $(wildcard $(BUILD_DIR)/ingenic-sdk-*))
define OPEN_TX_ISP_SDK_COMPAT_TREE
	mkdir -p $(@D)/external/ingenic-sdk/3.10.14/isp \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/include \
		$(@D)/external/ingenic-sdk/include
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/isp/$(SOC_FAMILY) \
		$(@D)/external/ingenic-sdk/3.10.14/isp/$(SOC_FAMILY)
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/isp/t20 \
		$(@D)/external/ingenic-sdk/3.10.14/isp/t20
	ln -sfn $(OPEN_TX_ISP_SDK_DIR)/common/sensor/include \
		$(@D)/external/ingenic-sdk/3.10.14/sensor-src/include
endef
OPEN_TX_ISP_PRE_BUILD_HOOKS += OPEN_TX_ISP_SDK_COMPAT_TREE
endif

$(eval $(kernel-module))
$(eval $(generic-package))
