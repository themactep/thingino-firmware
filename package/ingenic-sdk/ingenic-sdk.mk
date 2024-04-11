INGENIC_SDK_SITE_METHOD = git
INGENIC_SDK_SITE = https://github.com/themactep/ingenic-sdk
INGENIC_SDK_VERSION = $(shell git ls-remote $(INGENIC_SDK_SITE) master | head -1 | cut -f1)
INGENIC_SDK_GIT_SUBMODULES = YES

INGENIC_SDK_LICENSE = GPL-3.0
INGENIC_SDK_LICENSE_FILES = LICENSE

INGENIC_SDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(SOC_FAMILY) \
	SENSOR_MODEL=$(SENSOR_MODEL) \
	KERNEL_VERSION=$(KERNEL_VERSION) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic

LINUX_CONFIG_LOCALVERSION = \
	$(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

ifeq ($(BR2_SOC_INGENIC_T10)$(BR2_SOC_INGENIC_T20)$(BR2_SOC_INGENIC_T30),y)
SENSOR_CONFIG_NAME = $(SENSOR_MODEL).bin
else
SENSOR_CONFIG_NAME = $(SENSOR_MODEL)-$(SOC_FAMILY).bin
endif

ifeq ($(CONFIG_SOC_T40)$(CONFIG_SOC_T41),y)
	LIBALOG_FILE = $(@D)/lib/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
else
	# Install libalog.so from T31 1.1.6 for every XBurst1 SoC
	# 40032d0802b86f3cfb0b2b13d866556e
	LIBALOG_FILE = $(@D)/lib/T31/lib/1.1.6/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/libalog.so
endif

define INGENIC_SDK_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/$(KERNEL_VERSION)
	touch $(TARGET_DIR)/lib/modules/$(KERNEL_VERSION)/modules.builtin.modinfo

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(@D)/lib/$(SOC_FAMILY_CAPS)/lib/$(SDK_VERSION)/$(SDK_LIBC_NAME)/$(SDK_LIBC_VERSION)/*.so
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(LIBALOG_FILE)

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -D $(@D)/sensor-iq/$(SOC_FAMILY)/$(SENSOR_MODEL).bin $(TARGET_DIR)/etc/sensor/$(SENSOR_CONFIG_NAME)
	echo $(SENSOR_MODEL) >$(TARGET_DIR)/etc/sensor/model

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_SDK_PKGDIR)/files/load_ingenic
endef

$(eval $(kernel-module))
$(eval $(generic-package))
