################################################################################
#
# ingenic-osdrv-t21
#
################################################################################

INGENIC_OSDRV_T21_VERSION =
INGENIC_OSDRV_T21_SITE =
INGENIC_OSDRV_T21_LICENSE = MIT
INGENIC_OSDRV_T21_LICENSE_FILES = LICENSE

define INGENIC_OSDRV_T21_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T21_PKGDIR)/files/sensor/$(SENSOR_MODEL).yaml
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T21_PKGDIR)/files/sensor/params/$(SENSOR_MODEL)-t21.bin
	echo $(SENSOR_MODEL) >$(TARGET_DIR)/etc/sensor/model

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T21_PKGDIR)/files/script/load*

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(INGENIC_OSDRV_T21_PKGDIR)/files/lib/*.so
endef

$(eval $(generic-package))
