WIFI_RTL8188FU_SITE_METHOD = git
WIFI_RTL8188FU_SITE = https://github.com/openipc/realtek-wlan
WIFI_RTL8188FU_SITE_BRANCH = rtl8188fu
WIFI_RTL8188FU_VERSION = $(shell git ls-remote $(WIFI_RTL8188FU_SITE) $(WIFI_RTL8188FU_SITE_BRANCH) | head -1 | cut -f1)

WIFI_RTL8188FU_LICENSE = GPL-2.0
WIFI_RTL8188FU_LICENSE_FILES = COPYING

WIFI_RTL8188FU_MODULE_MAKE_OPTS = \
	CONFIG_RTL8188FU=m \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR)

define WIFI_RTL8188FU_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211,y)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL_HT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_DEFAULT_MINSTREL)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211_RC_DEFAULT,"minstrel_ht")
endef

$(eval $(kernel-module))
$(eval $(generic-package))
