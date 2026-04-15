WIFI_ATBM6062U_SITE_METHOD = git
ifeq ($(KERNEL_VERSION),3.10.14)
# Kernel 3.10 - upstream source with kernel-module build system
WIFI_ATBM6062U_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_ATBM6062U_SITE_BRANCH = atbm-606x
WIFI_ATBM6062U_VERSION = 4164499b15fb28d1f1fa694088f42dc2493f377e

ATBM6062U_MODULE_NAME = atbm6062u
ATBM6062U_MODULE_OPTS = atbm_printk_mask=0

WIFI_ATBM6062U_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR)
else
# Kernel 4.4+ - opensensor fork with kernel 4.4 compat and WPA3 support
WIFI_ATBM6062U_SITE = https://github.com/opensensor/atbm-wifi
WIFI_ATBM6062U_SITE_BRANCH = atbm-606x-clean
WIFI_ATBM6062U_VERSION = 663cba86c32f6f20dc3036b3c8a19c36627af2df

# Build using the driver's custom build system (Makefile.build.customer)
# This provides WPA3 support via backported cfg80211/mac80211
define WIFI_ATBM6062U_BUILD_CMDS
	$(MAKE) -C $(@D) \
		KERDIR=$(LINUX_DIR) \
		arch=$(KERNEL_ARCH) \
		CROSS_COMPILE=$(TARGET_CROSS) \
		install
endef

define WIFI_ATBM6062U_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)/extra
	$(INSTALL) -m 0644 $(@D)/driver_install/cfg80211.ko \
		$(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)/extra/cfg80211.ko
	$(INSTALL) -m 0644 $(@D)/driver_install/atbm6062u.ko \
		$(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)/extra/atbm6062u.ko
endef
endif

WIFI_ATBM6062U_LICENSE = GPL-2.0

ifeq ($(KERNEL_VERSION),3.10.14)
define WIFI_ATBM6062U_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	# Disable kernel's CFG80211, driver provides its own
	$(call KCONFIG_DISABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211,y)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_MINSTREL_HT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_MAC80211_RC_DEFAULT_MINSTREL)
	$(call KCONFIG_SET_OPT,CONFIG_MAC80211_RC_DEFAULT,"minstrel_ht")
endef
else
define WIFI_ATBM6062U_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	# Disable kernel's CFG80211/MAC80211 - driver provides its own backported version
	$(call KCONFIG_DISABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_DISABLE_OPT,CONFIG_MAC80211)
endef
endif

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

ifeq ($(KERNEL_VERSION),3.10.14)
define WIFI_ATBM6062U_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -D -m 0644 $(@D)/firmware/cronus_IPC_NOTXCONRIM_NoBLE_USB_svn19514_24M_wifi6phy_DCDC.bin \
		$(TARGET_DIR)/usr/lib/firmware/$(call qstrip,$(ATBM6062U_MODULE_NAME))_fw.bin
endef
else
define WIFI_ATBM6062U_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/usr/lib/modules/$(LINUX_VERSION_PROBED)$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -d $(TARGET_DIR)/usr/lib/firmware
	$(INSTALL) -m 0644 $(@D)/firmware/cronus_IPC_NOTXCONRIM_NoBLE_USB_svn19514_24M_wifi6phy_DCDC.bin \
		$(TARGET_DIR)/usr/lib/firmware/atbm6062u_fw.bin
endef
endif

WIFI_ATBM6062U_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6062U_INSTALL_CONFIGS

ifeq ($(KERNEL_VERSION),3.10.14)
define WIFI_ATBM6062U_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(@D)/configs/atbm6062u.config \
		$(@D)/.config
endef
WIFI_ATBM6062U_PRE_CONFIGURE_HOOKS += WIFI_ATBM6062U_COPY_CONFIG
$(eval $(kernel-module))
else
define WIFI_ATBM6062U_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(@D)/configs/atbm6062u.config \
		$(@D)/.config
	$(SED) 's/CONFIG_CPTCFG_CFG80211_WEXT=y/# CONFIG_CPTCFG_CFG80211_WEXT is not set/' $(@D)/.config
endef
WIFI_ATBM6062U_PRE_BUILD_HOOKS += WIFI_ATBM6062U_COPY_CONFIG
endif
$(eval $(generic-package))
