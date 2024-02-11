################################################################################
#
# ingenic-osdrv-t30
#
################################################################################

INGENIC_OSDRV_T30_VERSION =
INGENIC_OSDRV_T30_SITE =
INGENIC_OSDRV_T30_LICENSE = MIT
INGENIC_OSDRV_T30_LICENSE_FILES = LICENSE

define INGENIC_OSDRV_T30_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T30_PKGDIR)/files/sensor/$(BR2_SENSOR_MODEL).yaml
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T30_PKGDIR)/files/sensor/params/$(BR2_SENSOR_MODEL).bin
	echo $(BR2_SENSOR_MODEL) >$(TARGET_DIR)/etc/sensor/model

	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/3.10.14__isvp_monkey_1.0__/ingenic
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_monkey_1.0__/ingenic $(INGENIC_OSDRV_T30_PKGDIR)/files/kmod/sensor_$(BR2_SENSOR_MODEL)_t30.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_monkey_1.0__/ingenic $(INGENIC_OSDRV_T30_PKGDIR)/files/kmod/audio.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_monkey_1.0__/ingenic $(INGENIC_OSDRV_T30_PKGDIR)/files/kmod/gpio.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_monkey_1.0__/ingenic $(INGENIC_OSDRV_T30_PKGDIR)/files/kmod/tx-isp-t30.ko

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T30_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(INGENIC_OSDRV_T30_PKGDIR)/files/lib/*.so
endef

$(eval $(generic-package))
