define WIFI_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_SET_OPT,CONFIG_RFKILL,y)
endef

define WIFI_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/init.d
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S36wireless
	$(INSTALL) -m 755 -t $(TARGET_DIR)/etc/init.d/ $(WIFI_PKGDIR)/files/S38wpa_supplicant

	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/sbin/
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/sbin $(WIFI_PKGDIR)/files/wlan
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlancli
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlaninfo
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlanrssi
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlansetup
	ln -sr $(TARGET_DIR)/usr/sbin/wlan $(TARGET_DIR)/usr/sbin/wlantemp

	$(INSTALL) -m 755 -d $(TARGET_DIR)/etc/network/interfaces.d
	$(INSTALL) -m 644 -t $(TARGET_DIR)/etc/network/interfaces.d/ $(WIFI_PKGDIR)/files/wlan0

	if [ "$(BR2_PACKAGE_THINGINO_KOPT_MMC1_PA_4BIT)" = "y" ]; then \
		$(INSTALL) -m 755 -D $(WIFI_PKGDIR)/files/mmc_gpio_pa $(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	else \
		$(INSTALL) -m 755 -D $(WIFI_PKGDIR)/files/mmc_gpio_pb $(TARGET_DIR)/usr/sbin/mmc_gpio ; \
	fi
endef

$(eval $(generic-package))
