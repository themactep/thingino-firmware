WIFI_SSV6158_SITE_METHOD = git
WIFI_SSV6158_SITE = https://github.com/wltechblog/wifi-ssv6158
WIFI_SSV6158_SITE_BRANCH = main
WIFI_SSV6158_VERSION = a2afa9d80568895edd8875841137103801b51859

WIFI_SSV6158_LICENSE = GPL-2.0
WIFI_SSV6158_LICENSE_FILES = COPYING

SSV6158_MODULE_NAME = ssv6158
SSV6158_MODULE_OPTS = stacfgpath=/usr/share/wifi/ssv6x5x-wifi.cfg

WIFI_SSV6158_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR) \
	KBUILD_TOP=$(@D)

# 7.3.3 (T31): built-in cfg80211/mac80211 push the kernel past the 2304 KiB
# partition, so build them as modules there; S11modules loads the driver
# with modprobe, which pulls them in via modules.dep.
ifeq ($(KERNEL_VERSION),7.3.3)
WIFI_SSV6158_80211 = m
else
WIFI_SSV6158_80211 = y
endif

define WIFI_SSV6158_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,$(WIFI_SSV6158_80211))
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211,$(WIFI_SSV6158_80211))
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL_HT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_DEFAULT_MINSTREL)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211_RC_DEFAULT,"minstrel_ht")
	$(if $(BR2_PACKAGE_THINGINO_BLUETOOTH), \
	    $(call KCONFIG_SET_OPT,CONFIG_BT,y), \
	    $(call KCONFIG_ENABLE_OPT,CONFIG_BT_HCIBTSDIO))
endef

define WIFI_SSV6158_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(WIFI_SSV6158_PKGDIR)/files/ssv6x5x-wifi.cfg \
		$(TARGET_DIR)/usr/share/wifi/ssv6x5x-wifi.cfg
endef

WIFI_SSV6158_PRE_CONFIGURE_HOOKS += WIFI_SSV6158_COPY_CONFIG

define WIFI_SSV6158_ENABLE_BLE_CONFIG
	echo 'ccflags-y += -DCONFIG_BLE' >> $(@D)/config_common.mak
endef

ifeq ($(BR2_PACKAGE_THINGINO_BLUETOOTH),y)
WIFI_SSV6158_PRE_CONFIGURE_HOOKS += WIFI_SSV6158_ENABLE_BLE_CONFIG
endif

# Pull in the 7.3 compatibility header before the driver's own includes.
define WIFI_SSV6158_73_COMPAT_INCLUDE
	for f in $(@D)/*.c $(@D)/smac/*.c $(@D)/hci/*.c $(@D)/ssvdevice/*.c \
		$$(find $(@D)/hwif -name '*.c' 2>/dev/null); do \
		$(SED) '1i #include <ssv_73_compat.h>' $$f; \
	done
endef

WIFI_SSV6158_POST_PATCH_HOOKS += WIFI_SSV6158_73_COMPAT_INCLUDE

$(eval $(kernel-module))
$(eval $(generic-package))
