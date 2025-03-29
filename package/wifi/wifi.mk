define WIFI_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_SET_OPT,CONFIG_RFKILL,y)
endef

define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/S36wireless \
		$(TARGET_DIR)/etc/init.d/S36wireless

	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/S38wpa_supplicant \
		$(TARGET_DIR)/etc/init.d/S38wpa_supplicant

	$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/wlan \
		$(TARGET_DIR)/usr/sbin/wlan

	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlancli
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlaninfo
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlanrssi
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlansetup
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlantemp

	$(INSTALL) -D -m 0644 $(WIFI_PKGDIR)/files/wlan0 \
		$(TARGET_DIR)/etc/network/interfaces.d/wlan0

	if [ "$(BR2_PACKAGE_THINGINO_KOPT_MMC1_PA_4BIT)" = "y" ]; then \
		$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/mmc_gpio_pa \
			$(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	else \
		$(INSTALL) -D -m 0755 $(WIFI_PKGDIR)/files/mmc_gpio_pb \
			$(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	fi
endef

$(eval $(generic-package))
