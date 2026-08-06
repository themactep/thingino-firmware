################################################################################
#
# wireguard-tools overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_WIREGUARD_TOOLS),y)

override WIREGUARD_TOOLS_VERSION = 1.0.20260223
override WIREGUARD_TOOLS_SOURCE = wireguard-tools-$(WIREGUARD_TOOLS_VERSION).tar.xz
override WIREGUARD_TOOLS_SITE = https://git.zx2c4.com/wireguard-tools/snapshot

# Use Thingino-maintained hash file when version is overridden.
override WIREGUARD_TOOLS_HASH_FILES = \
	$(THINGINO_EXTERNAL_PATH)/package/all-patches/wireguard-tools/wireguard-tools.hash

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
WIREGUARD_TOOLS_DEPENDENCIES += thingino-webui

define WIREGUARD_TOOLS_INSTALL_WEBUI
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/www/config-wireguard.html \
		$(TARGET_DIR)/var/www/config-wireguard.html
	$(INSTALL) -D -m 0644 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/www/a/config-wireguard.js \
		$(TARGET_DIR)/var/www/a/config-wireguard.js
	$(INSTALL) -D -m 0644 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/www/a/wireguard.svg \
		$(TARGET_DIR)/var/www/a/wireguard.svg
	$(INSTALL) -D -m 0755 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/www/x/json-config-wireguard.cgi \
		$(TARGET_DIR)/var/www/x/json-config-wireguard.cgi
	$(INSTALL) -D -m 0755 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/www/x/json-wireguard.cgi \
		$(TARGET_DIR)/var/www/x/json-wireguard.cgi
	$(INSTALL) -D -m 0644 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/wireguard.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/wireguard.webui.json
endef
WIREGUARD_TOOLS_POST_INSTALL_TARGET_HOOKS += WIREGUARD_TOOLS_INSTALL_WEBUI
endif

define WIREGUARD_TOOLS_INSTALL_SCRIPTS
	$(INSTALL) -D -m 0755 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/S42wireguard \
		$(TARGET_DIR)/etc/init.d/S42wireguard
	$(INSTALL) -D -m 0755 $(THINGINO_EXTERNAL_PATH)/package/thingino-wireguard-tools/files/wireguard-watchdog \
		$(TARGET_DIR)/usr/sbin/wireguard-watchdog
endef
WIREGUARD_TOOLS_POST_INSTALL_TARGET_HOOKS += WIREGUARD_TOOLS_INSTALL_SCRIPTS

endif # BR2_PACKAGE_WIREGUARD_TOOLS
