################################################################################
#
# mosquitto overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_MOSQUITTO),y)

# Keep Buildroot mosquitto pinned to the version vetted for Thingino.
override MOSQUITTO_VERSION = 2.0.22
override MOSQUITTO_SITE = https://sources.buildroot.net/mosquitto

# Unless the Thingino-specific broker option is enabled, skip building the
# upstream broker even though the Buildroot symbol stays default-on.
ifneq ($(BR2_PACKAGE_THINGINO_MOSQUITTO_BROKER),y)

override MOSQUITTO_MAKE_DIRS = lib client

override define MOSQUITTO_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) $(TARGET_CONFIGURE_OPTS) DIRS="$(MOSQUITTO_MAKE_DIRS)" \
		$(MOSQUITTO_MAKE_OPTS) DESTDIR=$(TARGET_DIR) install
	rm -f $(TARGET_DIR)/etc/mosquitto/*.example
endef

override define MOSQUITTO_INSTALL_INIT_SYSV
endef

override define MOSQUITTO_INSTALL_INIT_SYSTEMD
endef

override MOSQUITTO_USERS =

endif # !BR2_PACKAGE_THINGINO_MOSQUITTO_BROKER

endif # BR2_PACKAGE_THINGINO_MOSQUITTO
