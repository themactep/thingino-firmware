################################################################################
#
# ingenic-osdrv-t23
#
################################################################################

INGENIC_OSDRV_T23_VERSION =
INGENIC_OSDRV_T23_SITE =
INGENIC_OSDRV_T23_LICENSE = MIT
INGENIC_OSDRV_T23_LICENSE_FILES = LICENSE

define INGENIC_OSDRV_T23_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T23_PKGDIR)/files/sensor/$(BR2_SENSOR_MODEL).yaml
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T23_PKGDIR)/files/sensor/params/$(BR2_SENSOR_MODEL)-t23.bin
	echo $(BR2_SENSOR_MODEL) >$(TARGET_DIR)/etc/sensor/model

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T23_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/ $(INGENIC_OSDRV_T23_PKGDIR)/files/lib/*.so
endef

$(eval $(generic-package))
