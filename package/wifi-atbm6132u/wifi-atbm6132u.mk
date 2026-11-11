WIFI_ATBM6132U_SITE_METHOD = git
ifeq ($(KERNEL_VERSION),3.10.14)
WIFI_ATBM6132U_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_ATBM6132U_SITE_BRANCH = master
WIFI_ATBM6132U_VERSION = 380838e871c793ff4feb19bd584d9508b162b835
else ifeq ($(KERNEL_VERSION),4.4.94)
WIFI_ATBM6132U_SITE = https://github.com/themactep/atbm-wifi
WIFI_ATBM6132U_SITE_BRANCH = clean
WIFI_ATBM6132U_VERSION = 04b41d38b712f7b655072c349ab014737b45adef
else
WIFI_ATBM6132U_SITE = https://github.com/gtxaspec/atbm-wifi
WIFI_ATBM6132U_SITE_BRANCH = master
WIFI_ATBM6132U_VERSION = 88454ec7f78fdf8ce69b1cfb7f2288251eb0bf82
endif

WIFI_ATBM6132U_LICENSE = GPL-2.0

ATBM6132U_MODULE_NAME = atbm6132u
ATBM6132U_MODULE_OPTS = atbm_printk_mask=0

WIFI_ATBM6132U_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR)

# A built-in cfg80211 pushes a 4.4 kernel past its 1600 KiB NOR partition;
# the driver only imports it, so modprobe loads cfg80211.ko ahead of it.
ifeq ($(KERNEL_VERSION),4.4.94)
WIFI_ATBM6132U_CFG80211 = m
else
WIFI_ATBM6132U_CFG80211 = y
endif

define WIFI_ATBM6132U_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,$(WIFI_ATBM6132U_CFG80211))
	# The driver builds its own mac80211 into the module and imports nothing
	# from the kernel's, so keep the kernel's out of the image.
	$(call KCONFIG_DISABLE_OPT,CONFIG_MAC80211)
endef

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

define WIFI_ATBM6132U_INSTALL_CONFIGS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo

	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/wifi
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/wifi \
		$(WIFI_ATBM_WIFI_PKGDIR)/files/*.txt

	$(INSTALL) -D -m 0644 $(@D)/firmware/firmware_mercurius_usb.bin \
		$(TARGET_DIR)/usr/lib/firmware/$(call qstrip,$(ATBM6132U_MODULE_NAME))_fw.bin
endef

WIFI_ATBM6132U_POST_INSTALL_TARGET_HOOKS += WIFI_ATBM6132U_INSTALL_CONFIGS

define WIFI_ATBM6132U_COPY_CONFIG
	$(INSTALL) -D -m 0644 $(@D)/configs/atbm6132u.config \
		$(@D)/.config
	$(SED) 's/^# CONFIG_ATBM_FUNC_P2P_ENABLE is not set/CONFIG_ATBM_FUNC_P2P_ENABLE=y/' \
		$(@D)/.config
endef

WIFI_ATBM6132U_PRE_CONFIGURE_HOOKS += WIFI_ATBM6132U_COPY_CONFIG

$(eval $(kernel-module))
$(eval $(generic-package))
