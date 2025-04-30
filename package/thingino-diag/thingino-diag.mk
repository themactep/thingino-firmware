define THINGINO_DIAG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/thingino-diag \
		$(TARGET_DIR)/usr/sbin/thingino-diag

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/soc \
		$(TARGET_DIR)/usr/sbin/soc

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/sensor \
		$(TARGET_DIR)/usr/sbin/sensor

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/sensor-info \
		$(TARGET_DIR)/usr/sbin/sensor-info

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/overlay-backup \
		$(TARGET_DIR)/usr/sbin/overlay-backup

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/ispmem-calc \
		$(TARGET_DIR)/usr/sbin/ispmem-calc

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/firstboot \
		$(TARGET_DIR)/usr/sbin/firstboot

	$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/usb-role \
		$(TARGET_DIR)/usr/sbin/usb-role

	if [ "$(SOC_FAMILY)" = "t40" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_DIAG_PKGDIR)/files/S02entropy \
		$(TARGET_DIR)/etc/init.d/S02entropy; \
	fi
endef

$(eval $(generic-package))
