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
		sed -i 's/set_gpio pb08 1 2/set_gpio pa08 3 2/' $(TARGET_DIR)/etc/init.d/S36wireless; \
		sed -i 's/set_gpio pb09 1 1/set_gpio pa09 3 1/' $(TARGET_DIR)/etc/init.d/S36wireless; \
		sed -i 's/set_gpio pb10 1 1/set_gpio pa10 3 1/' $(TARGET_DIR)/etc/init.d/S36wireless; \
		sed -i 's/set_gpio pb11 1 1/set_gpio pa11 3 1/' $(TARGET_DIR)/etc/init.d/S36wireless; \
		sed -i 's/set_gpio pb13 1 1/set_gpio pa16 3 1/' $(TARGET_DIR)/etc/init.d/S36wireless; \
		sed -i 's/set_gpio pb14 1 1/set_gpio pa17 3 1/' $(TARGET_DIR)/etc/init.d/S36wireless; \
	fi
endef

$(eval $(generic-package))
