WIFI_AIC8800_SITE_METHOD = git
WIFI_AIC8800_SITE = https://github.com/gtxaspec/aic8800-wifi
WIFI_AIC8800_SITE_BRANCH = master
WIFI_AIC8800_VERSION = 96cd509a9b6282d4f55adf2b394801ae9ae22599

WIFI_AIC8800_LICENSE = GPL-2.0

define WIFI_AIC8800_LINUX_CONFIG_FIXUPS
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

# USB driver path
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_USB),y)
WIFI_AIC8800_MODULE_SUBDIRS = USB/driver_fw/drivers/aic8800
endif

# SDIO driver path
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_SDIO),y)
WIFI_AIC8800_MODULE_SUBDIRS = SDIO/driver_fw/driver/aic8800
endif

# PCIE driver paths
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_PCIE),y)
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80),y)
WIFI_AIC8800_MODULE_SUBDIRS = PCIE/driver_fw/driver/aic8800/aic8800_fdrv
endif
ifeq ($(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80X2),y)
WIFI_AIC8800_MODULE_SUBDIRS = PCIE/driver_fw/driver/aic8800d80x2/aic8800_fdrv
endif
endif

LINUX_CONFIG_LOCALVERSION = $(shell awk -F "=" '/^CONFIG_LOCALVERSION=/ {print $$2}' $(BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE))

WIFI_AIC8800_FW_BASEDIR = $(TARGET_DIR)/lib/firmware
WIFI_AIC8800_FW_DIRS = aic8800 aic8800D80 aic8800D80X2 aic8800DC

WIFI_AIC8800_USB_8800_FW_DIR = USB/driver_fw/fw/aic8800
WIFI_AIC8800_USB_8800_FW_FILES = \
	aic_userconfig.txt \
	fmacfw.bin \
	fmacfw_m2d.bin \
	fmacfw_no_msg_ep.bin \
	fmacfw_no_msg_ep_rf.bin \
	fmacfw_rf.bin \
	fw_adid.bin \
	fw_adid_rf.bin \
	fw_adid_u03.bin \
	fw_ble_scan.bin \
	fw_ble_scan_ad_filter.bin \
	fw_ble_scan_ad_filter_dcdc.bin \
	fw_ble_scan_ad_filter_ldo.bin \
	fw_patch.bin \
	fw_patch_rf.bin \
	fw_patch_table.bin \
	fw_patch_table_u03.bin \
	fw_patch_u03.bin \
	m2d_ota.bin

WIFI_AIC8800_USB_8800D80_FW_DIR = USB/driver_fw/fw/aic8800D80
# Minimal subset required for normal operation (see aic_compat_8800d80.c)
WIFI_AIC8800_USB_8800D80_FW_FILES = \
	aic_userconfig_8800d80.txt \
	fmacfw_8800d80_h_u02.bin \
	fmacfw_8800d80_u02.bin \
	fw_adid_8800d80_u02.bin \
	fw_patch_8800d80_u02.bin \
	fw_patch_8800d80_u02_ext0.bin \
	fw_patch_table_8800d80_u02.bin

WIFI_AIC8800_USB_8800D80X2_FW_DIR = USB/driver_fw/fw/aic8800D80X2
WIFI_AIC8800_USB_8800D80X2_FW_FILES = \
	aic_powerlimit_8800d80x2.txt \
	aic_userconfig_8800d80x2.txt \
	fmacfw_8800d80x2.bin \
	fw_adid_8800d80x2_u03.bin \
	fw_patch_8800d80x2_u03.bin \
	fw_patch_table_8800d80x2_u03.bin \
	lmacfw_rf_8800d80x2.bin

WIFI_AIC8800_USB_8800DC_FW_DIR = USB/driver_fw/fw/aic8800DC
WIFI_AIC8800_USB_8800DC_FW_FILES = \
	aic_powerlimit_8800dc.txt \
	aic_powerlimit_8800dw.txt \
	aic_userconfig_8800dc.txt \
	aic_userconfig_8800dw.txt \
	fmacfw_calib_8800dc_h_u02.bin \
	fmacfw_calib_8800dc_u02.bin \
	fmacfw_patch_8800dc_h_u02.bin \
	fmacfw_patch_8800dc_ipc_u02.bin \
	fmacfw_patch_8800dc_u02.bin \
	fmacfw_patch_tbl_8800dc_h_u02.bin \
	fmacfw_patch_tbl_8800dc_ipc_u02.bin \
	fmacfw_patch_tbl_8800dc_u02.bin \
	fw_adid_8800dc_u02.bin \
	fw_adid_8800dc_u02h.bin \
	fw_patch_8800dc_u02.bin \
	fw_patch_8800dc_u02h.bin \
	fw_patch_table_8800dc_u02.bin \
	fw_patch_table_8800dc_u02h.bin \
	lmacfw_rf_8800dc.bin

WIFI_AIC8800_SDIO_8800_FW_DIR = SDIO/driver_fw/fw/aic8800
WIFI_AIC8800_SDIO_8800_FW_FILES = \
	aic_userconfig.txt \
	fmacfw.bin \
	fmacfw_8800m_custmsg.bin \
	fmacfw_patch.bin \
	fmacfw_rf.bin \
	fmacfwbt.bin \
	fw_adid.bin \
	fw_adid_u03.bin \
	fw_patch.bin \
	fw_patch_table.bin \
	fw_patch_table_u03.bin \
	fw_patch_test.bin \
	fw_patch_u03.bin

WIFI_AIC8800_SDIO_8800D80_FW_DIR = SDIO/driver_fw/fw/aic8800D80
WIFI_AIC8800_SDIO_8800D80_FW_FILES = \
	aic_userconfig_8800d80.txt \
	fmacfw_8800d80_h_u02.bin \
	fmacfw_8800d80_u02.bin \
	fmacfwbt_8800d80_h_u02.bin \
	fmacfwbt_8800d80_u02.bin \
	fw_adid_8800d80_u02.bin \
	fw_patch_8800d80_u02.bin \
	fw_patch_8800d80_u02_ext0.bin \
	fw_patch_table_8800d80_u02.bin \
	lmacfw_rf_8800d80_u02.bin

WIFI_AIC8800_SDIO_8800DC_FW_DIR = SDIO/driver_fw/fw/aic8800DC
WIFI_AIC8800_SDIO_8800DC_FW_FILES = \
	aic_userconfig_8800dc.txt \
	aic_userconfig_8800dw.txt \
	fmacfw_calib_8800dc_hbt_u02.bin \
	fmacfw_calib_8800dc_h_u02.bin \
	fmacfw_calib_8800dc_u02.bin \
	fmacfw_patch_8800dc_hbt_u02.bin \
	fmacfw_patch_8800dc_h_u02.bin \
	fmacfw_patch_8800dc_ipc_u02.bin \
	fmacfw_patch_8800dc_u02.bin \
	fmacfw_patch_tbl_8800dc_hbt_u02.bin \
	fmacfw_patch_tbl_8800dc_h_u02.bin \
	fmacfw_patch_tbl_8800dc_ipc_u02.bin \
	fmacfw_patch_tbl_8800dc_u02.bin \
	fw_adid_8800dc_u02.bin \
	fw_adid_8800dc_u02h.bin \
	fw_patch_8800dc_u02.bin \
	fw_patch_8800dc_u02h.bin \
	fw_patch_table_8800dc_u02.bin \
	fw_patch_table_8800dc_u02h.bin \
	lmacfw_rf_8800dc.bin

WIFI_AIC8800_PCIE_8800D80_FW_DIR = PCIE/driver_fw/fw/aic8800D80
WIFI_AIC8800_PCIE_8800D80_FW_FILES = \
	aic_userconfig_8800d80.txt \
	fmacfw_8800D80_pcie.bin \
	fmacfwbt_8800D80_pcie.bin \
	fw_adid_8800d80_u02.bin \
	fw_patch_8800d80_u02.bin \
	fw_patch_table_8800d80_u02.bin \
	lmacfw_rf_pcie.bin

WIFI_AIC8800_PCIE_8800D80X2_FW_DIR = PCIE/driver_fw/fw/aic8800D80X2
WIFI_AIC8800_PCIE_8800D80X2_FW_FILES = \
	aic_userconfig_8800d80x2.txt \
	fmacfw_8800D80X2_pcie.bin \
	fw_adid_8800d80x2_u03.bin \
	fw_patch_8800d80x2_u03.bin \
	fw_patch_table_8800d80x2_u03.bin \
	lmacfw_rf_8800D80X2_pcie.bin

WIFI_AIC8800_ALL_FW_FILES = $(sort \
	$(WIFI_AIC8800_USB_8800_FW_FILES) \
	$(WIFI_AIC8800_USB_8800D80_FW_FILES) \
	$(WIFI_AIC8800_USB_8800D80X2_FW_FILES) \
	$(WIFI_AIC8800_USB_8800DC_FW_FILES) \
	$(WIFI_AIC8800_SDIO_8800_FW_FILES) \
	$(WIFI_AIC8800_SDIO_8800D80_FW_FILES) \
	$(WIFI_AIC8800_SDIO_8800DC_FW_FILES) \
	$(WIFI_AIC8800_PCIE_8800D80_FW_FILES) \
	$(WIFI_AIC8800_PCIE_8800D80X2_FW_FILES))

define WIFI_AIC8800_INSTALL_FILELIST
	for f in $(2); do \
		src="$(@D)/$(1)/$$f"; \
		if [ ! -f "$$src" ]; then \
			echo "wifi-aic8800: missing firmware file $$src" >&2; \
			exit 1; \
		fi; \
		$(INSTALL) -m 0644 "$$src" $(WIFI_AIC8800_FW_BASEDIR)/; \
		if [ -n "$(3)" ]; then \
			$(INSTALL) -m 0755 -d $(WIFI_AIC8800_FW_BASEDIR)/$(3); \
			ln -sf ../$$f $(WIFI_AIC8800_FW_BASEDIR)/$(3)/$$f; \
		fi; \
	done
endef

define WIFI_AIC8800_INSTALL_FIRMWARE
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)
	touch $(TARGET_DIR)/lib/modules/3.10.14$(LINUX_CONFIG_LOCALVERSION)/modules.builtin.modinfo
	$(INSTALL) -m 0755 -d $(WIFI_AIC8800_FW_BASEDIR)
	for d in $(WIFI_AIC8800_FW_DIRS); do \
		rm -rf $(WIFI_AIC8800_FW_BASEDIR)/$$d; \
	done
	for f in $(WIFI_AIC8800_ALL_FW_FILES); do \
		rm -f $(WIFI_AIC8800_FW_BASEDIR)/$$f; \
	done

	# USB Models
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_USB_8800_FW_DIR),$(WIFI_AIC8800_USB_8800_FW_FILES),aic8800); \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800D80)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_USB_8800D80_FW_DIR),$(WIFI_AIC8800_USB_8800D80_FW_FILES),aic8800D80); \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800D80X2)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_USB_8800D80X2_FW_DIR),$(WIFI_AIC8800_USB_8800D80X2_FW_FILES),aic8800D80X2); \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_USB_8800DC)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_USB_8800DC_FW_DIR),$(WIFI_AIC8800_USB_8800DC_FW_FILES),aic8800DC); \
	fi

	# SDIO Models
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_SDIO_8800)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_SDIO_8800_FW_DIR),$(WIFI_AIC8800_SDIO_8800_FW_FILES),aic8800); \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_SDIO_8800D80)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_SDIO_8800D80_FW_DIR),$(WIFI_AIC8800_SDIO_8800D80_FW_FILES),aic8800D80); \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_SDIO_8800DC)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_SDIO_8800DC_FW_DIR),$(WIFI_AIC8800_SDIO_8800DC_FW_FILES),aic8800DC); \
	fi

	# PCIE Models
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_PCIE_8800D80_FW_DIR),$(WIFI_AIC8800_PCIE_8800D80_FW_FILES),aic8800D80); \
	fi
	if [ "$(BR2_PACKAGE_WIFI_AIC8800_PCIE_8800D80X2)" = "y" ]; then \
		$(call WIFI_AIC8800_INSTALL_FILELIST,$(WIFI_AIC8800_PCIE_8800D80X2_FW_DIR),$(WIFI_AIC8800_PCIE_8800D80X2_FW_FILES),aic8800D80X2); \
	fi
endef

WIFI_AIC8800_POST_INSTALL_TARGET_HOOKS += WIFI_AIC8800_INSTALL_FIRMWARE

$(eval $(kernel-module))
$(eval $(generic-package))
