################################################################################
#
# busybox ifplugd overrides for Thingino
#
################################################################################

# Buildroot's busybox installs a long-option S41ifplugd (broken with our
# busybox, CONFIG_LONG_OPTS is off) and ships no action script. Replace it
# with our short-option init script plus the missing action script. The
# install stays gated on CONFIG_IFPLUGD, which thingino-ethernet (wired)
# and usbnet (USB dongle) enable.
ifeq ($(BR2_PACKAGE_IFPLUGD),)
override define BUSYBOX_INSTALL_IFPLUGD_SCRIPT
	if grep -q CONFIG_IFPLUGD=y $(@D)/.config; then \
		$(INSTALL) -m 0755 -D $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-ethernet/files/S41ifplugd \
			$(TARGET_DIR)/etc/init.d/S41ifplugd; \
		$(INSTALL) -m 0755 -D $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-ethernet/files/ifplugd.action \
			$(TARGET_DIR)/etc/ifplugd/ifplugd.action; \
	fi
endef
endif
