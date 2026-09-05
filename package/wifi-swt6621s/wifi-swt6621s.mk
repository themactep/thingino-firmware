# Seekwave SWT6621S (SV6160LITE) USB wifi driver
# Driver source lives in its own repo (thingino policy: no driver sources
# in the firmware tree); this package is a thin git wrapper around it.
# Repo: https://github.com/WLTB-Gino/swt6621s
#
# Naming: package-infrastructure variables must use the FULL package prefix
# (WIFI_SWT6621S_*, derived from the package name wifi-swt6621s), matching
# the wifi-rtl8733bu reference. The only short-prefixed variables are
# SWT6621S_MODULE_NAME/SWT6621S_MODULE_OPTS: package/wifi/wifi.mk looks
# those up as $(WIFI_DRIVER_PREFIX)_MODULE_NAME with the prefix taken from
# BR2_PACKAGE_WIFI_SWT6621S.

WIFI_SWT6621S_VERSION = 5ed800e820730335d4ad2a168d69babe136343e5
WIFI_SWT6621S_SITE_METHOD = git
WIFI_SWT6621S_SITE = https://github.com/WLTB-Gino/swt6621s
WIFI_SWT6621S_SITE_BRANCH = main
WIFI_SWT6621S_LICENSE = GPL-2.0
WIFI_SWT6621S_LICENSE_FILES = LICENSE

# One kbuild invocation from the repo root builds both modules: the root
# Makefile exports skw_extra_flags/skw_extra_symbols consumed by both leaf
# Makefiles, then fans out via obj-m += drivers/.
WIFI_SWT6621S_MODULE_MAKE_OPTS = \
	CONFIG_SEEKWAVE_BSP_DRIVERS=m \
	CONFIG_SKW_USB=m \
	CONFIG_WLAN_VENDOR_SWT6621S=m \
	CONFIG_SWT6621S_DFS_MASTER=y

# S36wireless probes this module. It must be the BSP (skw_usb_lite), NOT the
# core: the two modules share no symbols (depmod cannot order them), and the
# BSP registers the sv6621s_wireless1 platform device and requests the core
# via request_module() (integrated in the driver repo commit cf2ecc7).
SWT6621S_MODULE_NAME = skw_usb_lite
SWT6621S_MODULE_OPTS =

# Driver requests (skw_boot.c): SWT6621S_IRAM_USB.bin, SWT6621S_DRAM_USB.bin,
# SWT6621S_NV_USB.bin. The drop ships the NV as the SHARE (single-antenna
# customer HW) variant, so install it under the requested name. The RFBIN
# files are factory-calibration artifacts and are not requested at runtime.
define WIFI_SWT6621S_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/lib/firmware
	$(INSTALL) -m 0644 $(@D)/firmware/USB-Firmware/SWT6621S_IRAM_USB.bin \
		$(@D)/firmware/USB-Firmware/SWT6621S_DRAM_USB.bin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 \
		$(@D)/firmware/USB-Firmware/NVBIN/NV_Related_to_customer_HW/SWT6621S_NV_USB_SHARE.bin \
		$(TARGET_DIR)/usr/lib/firmware/SWT6621S_NV_USB.bin
endef

$(eval $(kernel-module))
$(eval $(generic-package))
