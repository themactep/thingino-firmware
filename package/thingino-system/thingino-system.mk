ifeq ($(BR2_PACKAGE_THINGINO_SYSTEM_SWAP),y)
define THINGINO_SYSTEM_BUSYBOX_CONFIG_FIXUPS_SWAP
	$(call KCONFIG_ENABLE_OPT,CONFIG_MKSWAP)
	$(call KCONFIG_ENABLE_OPT,CONFIG_FEATURE_MKSWAP_UUID)
	$(call KCONFIG_ENABLE_OPT,CONFIG_SWAPON)
	$(call KCONFIG_ENABLE_OPT,CONFIG_SWAPOFF)
	$(call KCONFIG_ENABLE_OPT,CONFIG_FEATURE_SWAPON_DISCARD)
endef
endif

define THINGINO_SYSTEM_INSTALL_TARGET_CMDS
	# Utilities always installed
	$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/soc \
		$(TARGET_DIR)/usr/sbin/soc

	$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/firstboot \
		$(TARGET_DIR)/usr/sbin/firstboot

	# Optional utilities
	if [ "$(BR2_PACKAGE_THINGINO_SYSTEM_USB_ROLE)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/usb-role \
			$(TARGET_DIR)/usr/sbin/usb-role; \
	fi

	if [ "$(BR2_PACKAGE_THINGINO_SYSTEM_ENTROPY_GENERATOR)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/S01entropy \
			$(TARGET_DIR)/etc/init.d/S01entropy; \
	fi

	if [ "$(BR2_PACKAGE_THINGINO_SYSTEM_SWAP)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/S35swap \
			$(TARGET_DIR)/etc/init.d/S35swap; \
	fi

	if [ "$(BR2_PACKAGE_THINGINO_SYSTEM_SENSOR_UTILS)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/sensor \
			$(TARGET_DIR)/usr/sbin/sensor; \
		$(INSTALL) -D -m 0755 $(THINGINO_SYSTEM_PKGDIR)/files/sensor-info \
			$(TARGET_DIR)/usr/sbin/sensor-info; \
	fi
endef

define THINGINO_SYSTEM_BUSYBOX_CONFIG_FIXUPS
    $(call THINGINO_SYSTEM_BUSYBOX_CONFIG_FIXUPS_SWAP)
endef

$(eval $(generic-package))
