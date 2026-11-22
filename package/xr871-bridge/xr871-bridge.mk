XR871_BRIDGE_VERSION = 0.1
XR871_BRIDGE_SITE_METHOD = local
XR871_BRIDGE_SITE = $(XR871_BRIDGE_PKGDIR)/files
XR871_BRIDGE_LICENSE = MIT

define XR871_BRIDGE_BUILD_CMDS
	$(TARGET_CC) $(TARGET_CFLAGS) -Os -Wall -Wextra -o $(@D)/xr871d \
		$(@D)/xr871d.c $(TARGET_LDFLAGS)
	$(TARGET_CC) $(TARGET_CFLAGS) -Os -Wall -Wextra -o $(@D)/xr871net \
		$(@D)/xr871net.c $(TARGET_LDFLAGS)
endef

# Started from rcF (F00, right after the sysinit mounts, before rcS):
# the XR871 power-cycles the SoC if no heartbeat arrives within ~6 s of
# power-on, so it cannot wait for the regular S-scripts.
define XR871_BRIDGE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/xr871d $(TARGET_DIR)/usr/sbin/xr871d
	$(INSTALL) -D -m 0755 $(@D)/xr871net $(TARGET_DIR)/usr/sbin/xr871net
	$(INSTALL) -D -m 0755 $(@D)/F00xr871d $(TARGET_DIR)/etc/init.d/F00xr871d
	$(INSTALL) -D -m 0755 $(@D)/wlan $(TARGET_DIR)/usr/sbin/wlan
	$(INSTALL) -D -m 0644 $(@D)/wlan0 $(TARGET_DIR)/etc/network/interfaces.d/wlan0
	$(INSTALL) -D -m 0755 $(@D)/S38xr871portal $(TARGET_DIR)/etc/init.d/S38xr871portal
	$(INSTALL) -D -m 0755 $(@D)/wpa_cli $(TARGET_DIR)/usr/sbin/wpa_cli
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/wlight $(TARGET_DIR)/usr/sbin/wlight
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/light-white $(TARGET_DIR)/usr/libexec/light/white
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/pir-light $(TARGET_DIR)/usr/libexec/xr871/pir
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/daynight-hook $(TARGET_DIR)/usr/libexec/xr871/daynight
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/standby $(TARGET_DIR)/usr/libexec/xr871/standby
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/streamled $(TARGET_DIR)/usr/libexec/xr871/streamled
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_PKGDIR)/files/S96xr871led $(TARGET_DIR)/etc/init.d/S96xr871led
	# Thingino's captive portal (package/wifi), served by S60uhttpd in
	# portal mode; S38xr871portal replaces S38wpa_supplicant's AP part
	$(INSTALL) -D -m 0644 $(XR871_BRIDGE_WIFI_FILES)/dnsd-portal.conf $(TARGET_DIR)/etc/dnsd-portal.conf
	$(INSTALL) -D -m 0644 $(XR871_BRIDGE_WIFI_FILES)/udhcpd-portal.conf $(TARGET_DIR)/etc/udhcpd-portal.conf
	$(foreach f,favicon.ico index.html portal.min.js portal.min.css logo.svg,\
		$(INSTALL) -D -m 0644 $(XR871_BRIDGE_WIFI_FILES)/$(f) $(TARGET_DIR)/var/www-portal/$(f)$(sep))
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_WIFI_FILES)/portal.cgi $(TARGET_DIR)/var/www-portal/x/portal.cgi
	$(INSTALL) -D -m 0755 $(XR871_BRIDGE_WIFI_FILES)/api.cgi $(TARGET_DIR)/var/www-portal/x/api.cgi
endef

XR871_BRIDGE_WIFI_FILES = $(XR871_BRIDGE_PKGDIR)/../wifi/files

# The thingino overlay ships its own /etc/inittab and is copied after the
# target-finalize hooks, so the earliest point to edit it is the rootfs
# fakeroot stage. Start xr871d right after /proc is mounted (~0.8 s after
# the kernel hands over) instead of waiting for rcF (~3.5 s later, after
# the jffs2 overlay scan). xr871net (wlan0) follows once /sys, /tmp and the
# hostname are set (~1.5 s before rcF), so wlan0 exists with the XR871
# MAC when S40network runs ifup (interfaces.d/wlan0: dhcp, or whatever the
# WebUI writes). F00xr871d stays as a fallback (pidof guards).
define XR871_BRIDGE_EARLY_INITTAB
	grep -q xr871d $(TARGET_DIR)/etc/inittab || sed -i '/^::sysinit:\/bin\/mount -t proc proc \/proc$$/a ::sysinit:/usr/sbin/xr871d -b' $(TARGET_DIR)/etc/inittab; grep -q xr871d $(TARGET_DIR)/etc/inittab
	grep -q xr871net $(TARGET_DIR)/etc/inittab || sed -i '/^::sysinit:\/bin\/hostname -F \/etc\/hostname$$/a ::sysinit:/usr/sbin/xr871net -b' $(TARGET_DIR)/etc/inittab; grep -q xr871net $(TARGET_DIR)/etc/inittab
endef
XR871_BRIDGE_ROOTFS_PRE_CMD_HOOKS += XR871_BRIDGE_EARLY_INITTAB

# Battery camera: the failsafe key window costs 2 s on every wake. Keep a
# 0.3 s window (the [f] key still works on the ttyS1 console).
define XR871_BRIDGE_SHORT_FAILSAFE
	if [ -f $(TARGET_DIR)/etc/init.d/F02failsafe ]; then \
		sed -i 's/stty -icanon min 0 time 20 -echo/stty -icanon min 0 time 3 -echo/' $(TARGET_DIR)/etc/init.d/F02failsafe; \
	fi
endef
XR871_BRIDGE_ROOTFS_PRE_CMD_HOOKS += XR871_BRIDGE_SHORT_FAILSAFE

# Battery camera: time to the first picture counts. timps only needs the ISP
# modules (S11modules), not the network, web UI, MQTT or HA services, so start
# it right after them (S13) instead of last (S95): ISP up at ~6 s instead of
# ~15 s after the kernel starts (measured on the ABUS, 2026-11-20).
define XR871_BRIDGE_EARLY_TIMPS
	if [ -f $(TARGET_DIR)/etc/init.d/S95timps ]; then \
		mv $(TARGET_DIR)/etc/init.d/S95timps $(TARGET_DIR)/etc/init.d/S13timps; \
	fi
endef
XR871_BRIDGE_ROOTFS_PRE_CMD_HOOKS += XR871_BRIDGE_EARLY_TIMPS

# wlan0 is a TAP interface fed by xr871net over SPI
define XR871_BRIDGE_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_ENABLE_OPT,CONFIG_TUN)
endef

$(eval $(generic-package))
