THINGINO_SOUNDS_SITE_METHOD = local
THINGINO_SOUNDS_SITE = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-sounds

THINGINO_SOUNDS_LICENSE = CC0
THINGINO_SOUNDS_LICENSE_FILES = LICENSE

THINGINO_SOUNDS_FORMAT=$(if $(BR2_PACKAGE_THINGINO_SOUNDS_FORMAT_G711),ulaw,opus)

define THINGINO_SOUNDS_INSTALL_TARGET_CMDS
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/usr/share/sounds

	# Buildroot shares one target dir across incremental rebuilds and never
	# removes files a package installed in a previous configuration. Switching
	# the format (e.g. OPUS -> G.711) would otherwise leave the old format's
	# files behind, shipping both sets and bloating a flash-constrained rootfs.
	# Clear this package's sound files (both formats) before installing so only
	# the selected format is ever present.
	rm -f $(TARGET_DIR)/usr/share/sounds/*.opus $(TARGET_DIR)/usr/share/sounds/*.ulaw $(TARGET_DIR)/usr/share/sounds/*.wav

	# welcome message
	if [ "$(BR2_PACKAGE_THINGINO_SOUNDS_STARTUP)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
		$(THINGINO_SOUNDS_PKGDIR)/files/thingino.$(THINGINO_SOUNDS_FORMAT); \
	fi

	# chimes
	if [ "$(BR2_PACKAGE_THINGINO_SOUNDS_CHIMES)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/chime_1.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/chime_2.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/chime_3.$(THINGINO_SOUNDS_FORMAT); \
	fi

	# common voice messages
	$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
		$(THINGINO_SOUNDS_PKGDIR)/files/motiondetectionactivated.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/motiondetectiondisactivated.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/timelapserecordingstarted.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/timelepserecordingstopped.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/videorecordingstarted.$(THINGINO_SOUNDS_FORMAT) \
		$(THINGINO_SOUNDS_PKGDIR)/files/videorecordingstopped.$(THINGINO_SOUNDS_FORMAT);

	# wifi-related voice messages
	if [ "$(BR2_PACKAGE_WIFI)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/configurationportalisdown.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/configurationportalisup.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/configurationportalmode.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/pleasepowercycletorestart.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/wificonnected.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/wificonnectionfailed.$(THINGINO_SOUNDS_FORMAT); \
	fi

	# wireguard-related voice messages
	if [ "$(BR2_PACKAGE_THINGINO_VPN_WIREGUARD)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/wireguardvpnisdown.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/wireguardvpnisup.$(THINGINO_SOUNDS_FORMAT); \
	fi

	if [ "$(BR2_THINGINO_DEV_DOORBELL)" = "y" ]; then \
		$(INSTALL) -m 0644 -t $(TARGET_DIR)/usr/share/sounds \
			$(THINGINO_SOUNDS_PKGDIR)/files/doorbell_1.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/doorbell_2.$(THINGINO_SOUNDS_FORMAT) \
			$(THINGINO_SOUNDS_PKGDIR)/files/doorbell_3.$(THINGINO_SOUNDS_FORMAT); \
	fi
endef

# S97sysupgrade (overlay/etc/init.d/, not owned by this package) plays the
# post-upgrade chime and references a @SOUND_EXT@ placeholder instead of a
# hardcoded extension, so it - like every other consumer of these sound
# files - only ever references the one format this image actually ships.
# Resolve it here, once, at build time: this package is what decides
# THINGINO_SOUNDS_FORMAT in the first place.
#
# Must be a ROOTFS_PRE_CMD_HOOKS entry, not TARGET_FINALIZE_HOOKS: overlay
# files (BR2_ROOTFS_OVERLAY, which is where S97sysupgrade actually comes
# from) are copied into TARGET_DIR at the END of target-finalize's own
# recipe, AFTER its TARGET_FINALIZE_HOOKS loop already ran - so a
# finalize hook never actually sees the overlay-placed file.
# ROOTFS_PRE_CMD_HOOKS runs per rootfs-image-format, on the copy rsync'd
# from the now-fully-finalized (overlay included) target tree.
define THINGINO_SOUNDS_FIX_SYSUPGRADE_SOUND
	if [ -f $(TARGET_DIR)/etc/init.d/S97sysupgrade ]; then sed -i "s,@SOUND_EXT@,$(THINGINO_SOUNDS_FORMAT),g" $(TARGET_DIR)/etc/init.d/S97sysupgrade; fi
endef
ROOTFS_PRE_CMD_HOOKS += THINGINO_SOUNDS_FIX_SYSUPGRADE_SOUND

$(eval $(generic-package))
