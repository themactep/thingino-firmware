################################################################################
#
# ingenic-osdrv-t20
#
################################################################################

INGENIC_OSDRV_T20_VERSION =
INGENIC_OSDRV_T20_SITE =
INGENIC_OSDRV_T20_LICENSE = MIT
INGENIC_OSDRV_T20_LICENSE_FILES = LICENSE

define INGENIC_OSDRV_T20_INSTALL_TARGET_CMDS
	# create directories
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/3.10.14/ingenic
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	# $(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/sensors/params

	# install files
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/script/S95ingenic
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14/ingenic $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/kmod/audio.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14/ingenic $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/kmod/audio2.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14/ingenic $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/kmod/sinfo.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14/ingenic $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/kmod/sensor_$(BR2_OPENIPC_SENSOR_MODEL).ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14/ingenic $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/kmod/tx-isp-$(BR2_OPENIPC_SOC_FAMILY).ko
	ln -sf tx-isp-$(BR2_OPENIPC_SOC_FAMILY).ko $(TARGET_DIR)/lib/modules/3.10.14/ingenic/tx-isp-$(BR2_OPENIPC_SOC_MODEL).ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/sensor/params/$(BR2_OPENIPC_SENSOR_MODEL).bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/sensor/$(BR2_OPENIPC_SENSOR_MODEL).yaml
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/script/load*
	# $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/sensors/params $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/sensor/params/*.bin
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(BR2_EXTERNAL_INGENIC_PATH)/../general/package/ingenic-osdrv-t20/files/lib/*.so
endef

$(eval $(generic-package))
