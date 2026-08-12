################################################################################
#
# open-tx-isp
#
################################################################################

OPEN_TX_ISP_SITE_METHOD = git
OPEN_TX_ISP_SITE = https://github.com/opensensor/open-tx-isp
OPEN_TX_ISP_SITE_BRANCH = main
OPEN_TX_ISP_VERSION = 939e79ddc1fdcc6526cb6b578dbd893d3969520a

# Upstream identifies the project as GPLv3 but does not currently ship a
# top-level license file for legal-info to collect.
OPEN_TX_ISP_LICENSE = GPL-3.0

OPEN_TX_ISP_DEPENDENCIES = linux

ifneq ($(KERNEL_VERSION_7),y)
OPEN_TX_ISP_DEPENDENCIES += ingenic-sdk
endif

# Mainline T31 uses the open ISP driver, but it still needs the sensor IQ blob
# from the matching Ingenic SDK.  The mainline AVPU package already fetches the
# pinned SDK tree, so reuse that source instead of downloading or duplicating
# the proprietary tuning data in this package.
ifeq ($(KERNEL_VERSION_7):$(SOC_FAMILY),y:t31)
OPEN_TX_ISP_DEPENDENCIES += ingenic-avpu
endif

# Build as out-of-tree kernel module
OPEN_TX_ISP_MODULE_SUBDIRS = driver/$(SOC_FAMILY)

ifeq ($(KERNEL_VERSION_7):$(SOC_FAMILY):$(SENSOR_1_MODEL),y:t31:gc2053)
OPEN_TX_ISP_MODULE_SUBDIRS += sensor-src/t31
endif

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

$(eval $(kernel-module))

ifeq ($(KERNEL_VERSION_7):$(SOC_FAMILY):$(SENSOR_1_MODEL),y:t31:gc2053)
define OPEN_TX_ISP_INSTALL_MAINLINE_LOADERS
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/etc/modules.d
	echo "tx_isp_t31 $(ISP_CLK) $(ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM) $(ISP_CH0_PRE_DEQUEUE_TIME) $(ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS) $(ISP_CH0_PRE_DEQUEUE_VALID_LINES) $(ISP_CH1_DEQUEUE_DELAY_TIME) $(ISP_MEMOPT) $(ISP_PRINT_LEVEL) $(BR2_ISP_PARAMS)" > $(TARGET_DIR)/etc/modules.d/20-isp
	echo "sensor_gc2053_t31 $(SENSOR_1_PARAMS)" > $(TARGET_DIR)/etc/modules.d/30-sensor
	$(INSTALL) -d -m 0755 $(TARGET_DIR)/usr/share/sensor
	if [ -n "$(call qstrip,$(BR2_SENSOR_1_IQ_FILE))" ]; then \
		iqsrc="$(BR2_EXTERNAL_THINGINO_PATH)/$(call qstrip,$(BR2_SENSOR_1_IQ_FILE))"; \
	elif [ -n "$(call qstrip,$(BR2_SENSOR_ISP_FW))" ] && \
	     [ -f "$(INGENIC_AVPU_DIR)/sensor-iq/t31/$(call qstrip,$(BR2_SENSOR_ISP_FW))/$(SENSOR_1_MODEL).bin" ]; then \
		iqsrc="$(INGENIC_AVPU_DIR)/sensor-iq/t31/$(call qstrip,$(BR2_SENSOR_ISP_FW))/$(SENSOR_1_MODEL).bin"; \
	else \
		iqsrc="$(INGENIC_AVPU_DIR)/sensor-iq/t31/$(SENSOR_1_MODEL).bin"; \
	fi; \
	test -f "$$iqsrc"; \
	$(INSTALL) -m 0644 "$$iqsrc" \
		$(TARGET_DIR)/usr/share/sensor/$(SENSOR_1_MODEL)-t31.bin
	ln -snf /usr/share/sensor $(TARGET_DIR)/etc/sensor
	echo "$(SENSOR_1_MODEL)" > $(TARGET_DIR)/usr/share/sensor/model
endef

OPEN_TX_ISP_POST_INSTALL_TARGET_HOOKS += OPEN_TX_ISP_INSTALL_MAINLINE_LOADERS
endif

$(eval $(generic-package))
