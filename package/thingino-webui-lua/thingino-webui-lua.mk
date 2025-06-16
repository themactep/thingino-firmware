THINGINO_WEBUI_LUA_SITE_METHOD = local
THINGINO_WEBUI_LUA_SITE = $(THINGINO_WEBUI_LUA_PKGDIR)/files
THINGINO_WEBUI_LUA_LICENSE = MIT
THINGINO_WEBUI_LUA_DEPENDENCIES = lua thingino-wolfssl

# No build commands needed - wolfSSL certificate generator is built by thingino-wolfssl package

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
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_LUA_PKGDIR)/files/S60uhttpd-lua \
		$(TARGET_DIR)/etc/init.d/S60uhttpd-lua

	# Install wolfSSL certificate generator (shell script)
	$(INSTALL) -D -m 0755 $(THINGINO_WEBUI_LUA_PKGDIR)/files/usr/bin/wolfssl-certgen \
		$(TARGET_DIR)/usr/bin/wolfssl-certgen

	# wolfSSL certificate generator (native) is now installed by thingino-wolfssl package
endef

$(eval $(generic-package))
