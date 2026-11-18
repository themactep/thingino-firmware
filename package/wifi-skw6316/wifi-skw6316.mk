################################################################################
#
# wifi-skw6316 - SeekWave SKW6316 prebuilt driver
#
################################################################################

WIFI_SKW6316_VERSION = 1.0
WIFI_SKW6316_SITE_METHOD = local
WIFI_SKW6316_SITE = $(WIFI_SKW6316_PKGDIR)/files

SKW6316_MODULE_NAME = skw6316
SKW6316_MODULE_OPTS =

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

define WIFI_SKW6316_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/extra
	touch $(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/skw6316.ko \
		$(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/extra/skw6316.ko
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/skw_usb_lite.ko \
		$(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/extra/skw_usb_lite.ko
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/lib/firmware
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/SWT6621S_DRAM_USB.bin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/SWT6621S_IRAM_USB.bin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/SWT6621S_SEEKWAVE_R04001.bin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/SEEKWAVE_NV_SWT6621S.bin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/sv6160lite.nvbin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/PHY_REG_PG.txt \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/modprobe.d
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/skw6316.conf \
		$(TARGET_DIR)/etc/modprobe.d/skw6316.conf
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/etc/sysctl.d
	$(INSTALL) -m 0644 $(WIFI_SKW6316_PKGDIR)/files/50-skw6316.conf \
		$(TARGET_DIR)/etc/sysctl.d/50-skw6316.conf
	# Create module dependency so skw_usb_lite loads before skw6316
	echo "extra/skw_usb_lite.ko:" >> \
		$(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.dep
	echo "extra/skw6316.ko: extra/skw_usb_lite.ko" >> \
		$(TARGET_DIR)/usr/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.dep
endef

define WIFI_SKW6316_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_NETDEVICES)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS_EXT)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_CORE)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PROC)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WEXT_PRIV)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211)
	$(call KCONFIG_ENABLE_OPT,CONFIG_CFG80211_WEXT)
endef

$(eval $(generic-package))
