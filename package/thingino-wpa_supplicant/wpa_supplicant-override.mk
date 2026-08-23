################################################################################
#
# wpa_supplicant overrides for Thingino
#
################################################################################

# Guard: only apply when Thingino overrides are requested
ifeq ($(BR2_PACKAGE_THINGINO_WPA_SUPPLICANT),y)

# Thingino disables these features globally (more aggressive than upstream Buildroot)
#WPA_SUPPLICANT_CONFIG_DISABLE += \
#	CONFIG_SMARTCARD \
#	CONFIG_PKCS12 \
#	CONFIG_CTRL_IFACE_DBUS_INTRO \
#	CONFIG_IEEE80211R \
#	CONFIG_DEBUG_FILE \
#	CONFIG_IEEE80211AC \
#	CONFIG_IEEE80211AX \
#	CONFIG_IEEE80211BE \
#	CONFIG_TDLS

# buildroot's WPA_SUPPLICANT_CONFIGURE_CMDS ends with a loop that re-adds any
# CONFIG_ENABLE symbol whose uncommented line is missing. CONFIG_P2P and
# CONFIG_MATCH_IFACE are in buildroot's ENABLE list (via AP_SUPPORT and the
# base list respectively), so after the DISABLE sed comments them out the loop
# appends them back as =y and they win. Disable them again after configure.
define THINGINO_WPA_SUPPLICANT_REDISABLE_P2P
	$(SED) 's/^\(CONFIG_P2P\)/#\1/' $(@D)/wpa_supplicant/.config
endef
define THINGINO_WPA_SUPPLICANT_REDISABLE_MATCH_IFACE
	$(SED) 's/^\(CONFIG_MATCH_IFACE\)/#\1/' $(@D)/wpa_supplicant/.config
endef

#WPA_SUPPLICANT_CONFIG_DISABLE += CONFIG_P2P
#WPA_SUPPLICANT_POST_CONFIGURE_HOOKS += THINGINO_WPA_SUPPLICANT_REDISABLE_P2P

#WPA_SUPPLICANT_CONFIG_DISABLE += CONFIG_MATCH_IFACE
#WPA_SUPPLICANT_POST_CONFIGURE_HOOKS += THINGINO_WPA_SUPPLICANT_REDISABLE_MATCH_IFACE

endif # BR2_PACKAGE_THINGINO_WPA_SUPPLICANT
