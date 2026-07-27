THINGINO_WEBUI_LUA_SITE_METHOD = local
THINGINO_WEBUI_LUA_SITE = $(THINGINO_WEBUI_LUA_PKGDIR)/files
THINGINO_WEBUI_LUA_LICENSE = MIT
THINGINO_WEBUI_LUA_DEPENDENCIES = lua

ifeq ($(BR2_PACKAGE_OPENSSL),y)
THINGINO_WEBUI_LUA_DEPENDENCIES += openssl
endif

define THINGINO_WEBUI_LUA_INSTALL_TARGET_CMDS
	# Install Lua web interface files
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/lua
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/lua/lib
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/lua/templates
	$(INSTALL) -m 0755 -d $(TARGET_DIR)/var/www/static/css
	cp -rv $(THINGINO_WEBUI_LUA_PKGDIR)/files/www/* $(TARGET_DIR)/var/www/

	# Set proper permissions (only if files exist)
	find $(TARGET_DIR)/var/www/lua -name "*.lua" -exec chmod 644 {} \; 2>/dev/null || true
	find $(TARGET_DIR)/var/www/lua/lib -name "*.lua" -exec chmod 644 {} \; 2>/dev/null || true
	find $(TARGET_DIR)/var/www/lua/templates -name "*.html" -exec chmod 644 {} \; 2>/dev/null || true
	find $(TARGET_DIR)/var/www/static -name "*.css" -exec chmod 644 {} \; 2>/dev/null || true
	[ -f $(TARGET_DIR)/var/www/index.html ] && chmod 644 $(TARGET_DIR)/var/www/index.html || true

	# Session storage will be created in /run/sessions by init script (tmpfs)

	# Install startup script for uhttpd with Lua support
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_LUA_PKGDIR)/files/etc/init.d/S60uhttpd-lua \
		$(TARGET_DIR)/etc/init.d/S60uhttpd-lua
endef

# Install SSL certificate generators conditionally
ifeq ($(BR2_PACKAGE_OPENSSL),y)
define THINGINO_WEBUI_LUA_INSTALL_OPENSSL_CERTGEN
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_LUA_PKGDIR)/files/usr/bin/openssl-certgen \
		$(TARGET_DIR)/usr/bin/openssl-certgen
endef
THINGINO_WEBUI_LUA_POST_INSTALL_TARGET_HOOKS += THINGINO_WEBUI_LUA_INSTALL_OPENSSL_CERTGEN
endif

$(eval $(generic-package))
