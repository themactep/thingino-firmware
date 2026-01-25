THINGINO_SOUNDS_SITE_METHOD = local
THINGINO_SOUNDS_SITE = $(BR2_EXTERNAL)/package/thingino-sounds

THINGINO_SOUNDS_LICENSE = CC0
THINGINO_SOUNDS_LICENSE_FILES = LICENSE

THINGINO_SOUNDS_FORMAT=opus

define THINGINO_SOUNDS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/sounds

	# welcome message
	if [ "$(BR2_PACKAGE_THINGINO_SOUNDS_STARTUP)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
		$(THINGINO_SOUNDS_PKGDIR)/files/thingino.$(THINGINO_SOUNDS_FORMAT); \
	fi

	# chimes
	if [ "$(BR2_PACKAGE_THINGINO_SOUNDS_CHIMES)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/chime_1.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/chime_2.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/chime_3.$(THINGINO_SOUNDS_FORMAT); \
	fi

	# common voice messages
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
		$(THINGINO_SOUNDS_PKGDIR)/files/motiondetectionactivated.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/motiondetectiondisactivated.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/timelapserecordingstarted.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/timelepserecordingstopped.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/videorecordingstarted.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/videorecordingstopped.$(THINGINO_SOUNDS_FORMAT);

	# wifi-related voice messages
	if [ "$(BR2_PACKAGE_WIFI)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/configurationportalisdown.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/configurationportalisup.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/configurationportalmode.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/pleasepowercycletorestart.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/wificonnected.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/wificonnectionfailed.$(THINGINO_SOUNDS_FORMAT); \
	fi

	# wireguard-related voice messages
	if [ "$(BR2_PACKAGE_THINGINO_VPN_WIREGUARD)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/wireguardvpnisdown.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/wireguardvpnisup.$(THINGINO_SOUNDS_FORMAT); \
	fi

	if [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/doorbell_1.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/doorbell_2.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/doorbell_3.$(THINGINO_SOUNDS_FORMAT); \
	fi
endef

$(eval $(generic-package))
