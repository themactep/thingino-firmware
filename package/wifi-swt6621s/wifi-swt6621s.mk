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

WIFI_SWT6621S_VERSION = aba0d26d1db3f24854bcca3d420cc98911f7e4ef
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
	CONFIG_WLAN_VENDOR_SWT6621S=m
# DFS master must stay OFF: on kernel 3.10 out-of-tree MAKE_OPTS are kbuild
# make-variables only (autoconf.h never sees them), so enabling it desyncs
# kbuild (adds skw_dfs.o) from the C preprocessor (skw_dfs.h still compiles
# its static-inline stub branch) -> duplicate-symbol errors; skw_dfs.c also
# calls the 4-arg cfg80211_cac_event (4.17+). DFS off = stubs inline no-ops.

# The driver is a full-mac (softmac) cfg80211 driver: its Kconfig says
# depends on CFG80211, and without the kernel wireless core built-in the
# module fails modpost with ~48 undefined wiphy/cfg80211 symbols and cannot
# insmod. MAC80211 stays off: the undefined-symbol list contains no
# ieee80211_alloc_hw-class symbols (this is a softmac, not full-mac, stack;
# the firmware handles the MAC layer). WEXT stays off too: the driver's
# cfg80211_wext_* / wireless_handlers call sites are self-gated behind
# CONFIG_CFG80211_WEXT_EXPORT / CONFIG_WIRELESS_EXT, neither of which we
# set (wpa_supplicant drives this via nl80211). WLAN_VENDOR_SWT6621S in
# MODULE_MAKE_OPTS is kbuild-only on 3.10 (see DFS note) and does NOT
# satisfy the driver's own Kconfig depends; the real dependency must be
# materialized in the kernel .config here.
define WIFI_SWT6621S_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_WLAN)
	$(call KCONFIG_ENABLE_OPT,CONFIG_WIRELESS)
	$(call KCONFIG_SET_OPT,CONFIG_CFG80211,y)
endef

# S36wireless probes this module. It must be the BSP (skw_usb_lite), NOT the
# core: the two modules share no symbols (depmod cannot order them), and the
# BSP registers the sv6621s_wireless1 platform device and requests the core
# via request_module() (integrated in the driver repo commit cf2ecc7).
SWT6621S_MODULE_NAME = skw_usb_lite
SWT6621S_MODULE_OPTS =

# Driver requests at runtime (verified from skw.log 2026-09-06 on the W3-U):
#   boot:   SWT6621S_IRAM_USB.bin, SWT6621S_DRAM_USB.bin, SWT6621S_NV_USB.bin
#   wifi:   SWT6621S_SEEKWAVE_R04001.bin (skw_calib_download; name is composed
#           at runtime in skw_core.c as <chipid>_<project>_R<vendor><rev>.bin
#           from the chip's efuse — this unit resolved R04001)
#           MISSING = probe FAILS HARD: driver calls skw_stop_wifi_service,
#           wlan0 never registers (this was the field failure).
#   config: swt6621s_wifi.dat — optional, absent from the vendor drop too;
#           driver keeps compiled-in defaults when it's missing (soft fail).
# The NV ships as the SHARE (single-antenna customer HW) variant, installed
# under the requested name. The RFBIN calib blob is chip/efuse-specific; a
# unit resolving a different Rxxxxx name would need that unit's factory calib.
define WIFI_SWT6621S_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/lib/firmware
	$(INSTALL) -m 0644 $(@D)/firmware/USB-Firmware/SWT6621S_IRAM_USB.bin \
		$(@D)/firmware/USB-Firmware/SWT6621S_DRAM_USB.bin \
		$(TARGET_DIR)/usr/lib/firmware/
	$(INSTALL) -m 0644 \
		$(@D)/firmware/USB-Firmware/NVBIN/NV_Related_to_customer_HW/SWT6621S_NV_USB_SHARE.bin \
		$(TARGET_DIR)/usr/lib/firmware/SWT6621S_NV_USB.bin
	$(INSTALL) -m 0644 \
		$(@D)/firmware/USB-Firmware/RFBIN/RF_Related_to_customer_HW/SWT6621S_SEEKWAVE_R04001.bin \
		$(TARGET_DIR)/usr/lib/firmware/
endef

$(eval $(kernel-module))
$(eval $(generic-package))
