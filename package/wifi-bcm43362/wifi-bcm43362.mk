WIFI_BCM43362_VERSION = 1.0
WIFI_BCM43362_SITE_METHOD = local
WIFI_BCM43362_SITE = $(WIFI_BCM43362_PKGDIR)
WIFI_BCM43362_LICENSE = Cypress, Broadcom
WIFI_BCM43362_DEPENDENCIES = linux-firmware

BCM43362_MODULE_NAME = brcmfmac
BCM43362_MODULE_OPTS =

define WIFI_BCM43362_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211_WEXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN_VENDOR_BROADCOM)
	$(call KCONFIG_SET_OPT,CONFIG_BRCMFMAC,m)
	$(call KCONFIG_ENABLE_OPT,CONFIG_BRCMFMAC_SDIO)
endef

# Only these two files: the linux-firmware Cypress/Broadcom options would
# install every chip's firmware. The AP6181 has no nvram of its own in
# linux-firmware; the AP6210's (same BCM43362, 26 MHz crystal) stands in.
define WIFI_BCM43362_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(LINUX_FIRMWARE_DIR)/cypress/cyfmac43362-sdio.bin \
		$(TARGET_DIR)/lib/firmware/brcm/brcmfmac43362-sdio.bin
	$(INSTALL) -D -m 0644 \
		"$(LINUX_FIRMWARE_DIR)/brcm/brcmfmac43362-sdio.cubietech,cubietruck.txt" \
		$(TARGET_DIR)/lib/firmware/brcm/brcmfmac43362-sdio.txt
endef

$(eval $(generic-package))
