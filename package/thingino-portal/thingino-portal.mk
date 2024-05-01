THINGINO_PORTAL_VERSION = 1.0

define THINGINO_PORTAL_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 0644 $(@D)/files/udhcpd.conf $(TARGET_DIR)/etc/udhcpd.conf
    $(INSTALL) -D -m 0644 $(@D)/files/wpa_ap.conf $(TARGET_DIR)/etc/wpa_ap.conf
endef

$(eval $(generic-package))
