THINGINO_PORTAL_LUA_SITE_METHOD = local
THINGINO_PORTAL_LUA_SITE = $(THINGINO_PORTAL_LUA_PKGDIR)/files
THINGINO_PORTAL_LUA_LICENSE = MIT
THINGINO_PORTAL_LUA_DEPENDENCIES = lua thingino-uhttpd thingino-wpa_supplicant

define THINGINO_PORTAL_LUA_INSTALL_TARGET_CMDS
	# Install portal web files
	$(INSTALL) -d $(TARGET_DIR)/var/www-portal/lua
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/www/index.html $(TARGET_DIR)/var/www-portal/index.html
	$(INSTALL) -m 0755 $(THINGINO_PORTAL_LUA_PKGDIR)/files/www/lua/portal.lua $(TARGET_DIR)/var/www-portal/lua/portal.lua

	# Install static assets
	$(INSTALL) -d $(TARGET_DIR)/var/www-portal/a
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/www/a/bootstrap.min.css $(TARGET_DIR)/var/www-portal/a/bootstrap.min.css
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/www/a/bootstrap.bundle.min.js $(TARGET_DIR)/var/www-portal/a/bootstrap.bundle.min.js
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/www/a/logo.svg $(TARGET_DIR)/var/www-portal/a/logo.svg
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/www/a/favicon.ico $(TARGET_DIR)/var/www-portal/a/favicon.ico

	# Install configuration files
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/etc/uhttpd-portal.conf $(TARGET_DIR)/etc/uhttpd-portal.conf
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/etc/dnsd-portal.conf $(TARGET_DIR)/etc/dnsd-portal.conf
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/etc/udhcpd-portal.conf $(TARGET_DIR)/etc/udhcpd-portal.conf
	$(INSTALL) -m 0644 $(THINGINO_PORTAL_LUA_PKGDIR)/files/etc/wpa-portal_ap.conf $(TARGET_DIR)/etc/wpa-portal_ap.conf

	# Install init script
	$(INSTALL) -D -m 0755 $(THINGINO_PORTAL_LUA_PKGDIR)/files/S41portal-lua $(TARGET_DIR)/etc/init.d/S41portal-lua
endef

# MT7601u wifi driver needs a PSK for the portal AP to function
ifeq ($(BR2_PACKAGE_WIFI_MT7601U),y)
define MODIFY_INSTALL_CONFIGS
	sed -i '/key_mgmt/s/NONE/WPA-PSK/' $(TARGET_DIR)/etc/wpa-portal_ap.conf
	sed -i '/network={/a\	psk="thingino"' $(TARGET_DIR)/etc/wpa-portal_ap.conf
endef
endif

THINGINO_PORTAL_LUA_POST_INSTALL_TARGET_HOOKS += MODIFY_INSTALL_CONFIGS

$(eval $(generic-package))
