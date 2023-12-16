################################################################################
#
# ingenic-osdrv-t21
#
################################################################################

INGENIC_OSDRV_T21_VERSION =
INGENIC_OSDRV_T21_SITE =
INGENIC_OSDRV_T21_LICENSE = MIT
INGENIC_OSDRV_T21_LICENSE_FILES = LICENSE

F = $(patsubst "%",%,$(BR2_OPENIPC_SOC_FAMILY))
S = $(patsubst "%",%,$(BR2_OPENIPC_SENSOR_MODEL))
SENSOR_SHA1 = $(patsubst "%",%,$(BR2_OPENIPC_SENSOR_KO_SHA1))
TX_ISP_SHA1 = $(patsubst "%",%,$(BR2_OPENIPC_TXISP_KO_SHA1))

define INGENIC_OSDRV_T21_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/sensor
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T21_PKGDIR)/files/sensor/$(S).yaml

	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/sensor $(INGENIC_OSDRV_T21_PKGDIR)/files/sensor/params/$(S)-$(F).bin

	$(INSTALL) -m 755 -d $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic

	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/audio.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/audioout.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/gpio.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/ircut.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/motor.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/reset.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/rled.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/sinfo.ko
	$(INSTALL) -m 644 -t $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/wifien.ko

	$(INSTALL) -m 644 $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/tx-isp-$(F).ko-$(TX_ISP_SHA1) $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic/tx-isp-$(F).ko

	$(INSTALL) -m 644 $(INGENIC_OSDRV_T21_PKGDIR)/files/kmod/sensor_$(S)_$(F).ko-$(SENSOR_SHA1) $(TARGET_DIR)/lib/modules/3.10.14__isvp_turkey_1.0__/ingenic/sensor_$(S)_$(F).ko

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T21_PKGDIR)/files/script/load*
	# $(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T21_PKGDIR)/files/script/ircut_demo
	# $(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(INGENIC_OSDRV_T21_PKGDIR)/files/sample/*

	# $(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/sensors/params
	# $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/sensors/params $(INGENIC_OSDRV_T21_PKGDIR)/files/sensor/params/*.bin

	# $(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib/sensors/params/WDR
	# $(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib/sensors/params/WDR $(INGENIC_OSDRV_T21_PKGDIR)/files/sensor/params/WDR/*.bin

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(INGENIC_OSDRV_T21_PKGDIR)/files/lib/*.so
endef

$(eval $(generic-package))
