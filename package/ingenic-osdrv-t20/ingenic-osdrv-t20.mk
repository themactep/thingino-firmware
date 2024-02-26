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
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T20_PKGDIR)/files/sensor/$(SENSOR_MODEL).yaml
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T20_PKGDIR)/files/sensor/params/$(SENSOR_MODEL).bin
	echo $(SENSOR_MODEL) >$(TARGET_DIR)/etc/sensor/model

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T20_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(INGENIC_OSDRV_T20_PKGDIR)/files/lib/*.so
endef

$(eval $(generic-package))
