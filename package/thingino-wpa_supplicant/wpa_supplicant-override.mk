################################################################################
#
# wpa_supplicant overrides for Thingino
#
################################################################################

# Guard: only apply when Thingino overrides are requested
ifeq ($(BR2_PACKAGE_THINGINO_WPA_SUPPLICANT),y)

# Thingino disables these features globally (more aggressive than upstream Buildroot)
WPA_SUPPLICANT_CONFIG_DISABLE += \
	CONFIG_SMARTCARD \
	CONFIG_PKCS12 \
	CONFIG_CTRL_IFACE_DBUS_INTRO \
	CONFIG_IEEE80211R \
	CONFIG_DEBUG_FILE \
	CONFIG_IEEE80211AC \
	CONFIG_IEEE80211AX \
	CONFIG_MATCH_IFACE \
	CONFIG_P2P \
	CONFIG_TDLS

endif # BR2_PACKAGE_THINGINO_WPA_SUPPLICANT
