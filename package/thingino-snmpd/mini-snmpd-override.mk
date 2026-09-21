################################################################################
#
# mini-snmpd overrides for Thingino
#
# thingino-snmpd is a thin integration layer: the daemon comes from
# Buildroot's mini-snmpd package, this file wires it into Thingino.
#
# IMPORTANT: this file is included through BR2_PACKAGE_OVERRIDE_FILE before
# mini-snmpd.mk runs, and mini-snmpd.mk assigns its variables with plain '=',
# so every variable we touch here needs 'override' or buildroot's assignment
# would wipe it (and, once overridden, later plain assignments are ignored).
#
################################################################################

# mini-snmpd.mk expands this Kconfig int straight into MAX_NR_INTERFACES.
# Force-building the package while its symbol is absent from .config (plain
# 'make mini-snmpd' / 'make rebuild-mini-snmpd' on a camera that does not
# select it) leaves the value empty, and the build then dies with
# "flexible array member not at end of struct". Supply the Kconfig default.
BR2_PACKAGE_MINI_SNMPD_INTERFACES ?= 8

ifeq ($(BR2_PACKAGE_THINGINO_SNMPD),y)

override MINI_SNMPD_DEPENDENCIES = host-pkgconf thingino-core

# --without-config drops the libConfuse dependency: everything is configured
# from /etc/thingino.json by the init script. It also disables the ethtool
# interface statistics backend, which needs the .conf parser.
override MINI_SNMPD_CONF_OPTS = \
	--with-interfaces=$(BR2_PACKAGE_MINI_SNMPD_INTERFACES) \
	--without-config \
	--without-systemd \
	--disable-test

ifeq ($(BR2_INET_IPV6),y)
override MINI_SNMPD_CONF_OPTS += --enable-ipv6
else
override MINI_SNMPD_CONF_OPTS += --disable-ipv6
endif

# Replace Buildroot's generic init script and /etc/default file with the
# Thingino one, which reads /etc/thingino.json.
override define MINI_SNMPD_INSTALL_ETC_DEFAULT
endef

# libConfuse may be selected for other packages; keep its example .conf out
# of the image since the daemon is built without --with-config.
override define MINI_SNMPD_INSTALL_CONFIG
endef

override define MINI_SNMPD_INSTALL_INIT_SYSV
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-snmpd/files/S60snmpd \
		$(TARGET_DIR)/etc/init.d/S60snmpd
endef

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
override MINI_SNMPD_DEPENDENCIES += thingino-webui

define THINGINO_SNMPD_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-snmpd/files/www/config-snmpd.html \
		$(TARGET_DIR)/var/www/config-snmpd.html
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-snmpd/files/www/a/config-snmpd.js \
		$(TARGET_DIR)/var/www/a/config-snmpd.js
	$(INSTALL) -D -m 0755 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-snmpd/files/www/x/json-config-snmpd.cgi \
		$(TARGET_DIR)/var/www/x/json-config-snmpd.cgi
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-snmpd/files/thingino-snmpd.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/thingino-snmpd.webui.json
endef
endif

define THINGINO_SNMPD_INSTALL_THINGINO_FILES
	# Stage defaults for later merge by thingino-core
	$(INSTALL) -D -m 0644 $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-snmpd/files/thingino-snmpd.json \
		$(TARGET_DIR)/usr/share/thingino-defaults/50-snmpd.json

	$(THINGINO_SNMPD_INSTALL_WWW_CMDS)
endef

MINI_SNMPD_POST_INSTALL_TARGET_HOOKS += THINGINO_SNMPD_INSTALL_THINGINO_FILES

endif # BR2_PACKAGE_THINGINO_SNMPD
