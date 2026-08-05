################################################################################
#
# thingino-snmpd - mini-snmpd wired into thingino
#
################################################################################

THINGINO_SNMPD_VERSION = 2.0
THINGINO_SNMPD_SOURCE = mini-snmpd-$(THINGINO_SNMPD_VERSION).tar.gz
THINGINO_SNMPD_SITE = https://github.com/troglobit/mini-snmpd/releases/download/v$(THINGINO_SNMPD_VERSION)

THINGINO_SNMPD_LICENSE = GPL-2.0
THINGINO_SNMPD_LICENSE_FILES = COPYING
THINGINO_SNMPD_CPE_ID_VENDOR = minisnmpd_project
THINGINO_SNMPD_CPE_ID_PRODUCT = minisnmpd

THINGINO_SNMPD_DEPENDENCIES = host-pkgconf thingino-core

# --without-config drops the libConfuse dependency: everything is
# configured from /etc/thingino.json by the init script. Disabling it
# also disables the ethtool interface statistics backend.
THINGINO_SNMPD_CONF_OPTS = \
	--without-config \
	--without-systemd \
	--disable-test \
	--with-interfaces=8

ifeq ($(BR2_INET_IPV6),y)
THINGINO_SNMPD_CONF_OPTS += --enable-ipv6
else
THINGINO_SNMPD_CONF_OPTS += --disable-ipv6
endif

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
THINGINO_SNMPD_DEPENDENCIES += thingino-webui

define THINGINO_SNMPD_INSTALL_WWW_CMDS
	$(INSTALL) -d $(TARGET_DIR)/var/www/a
	$(INSTALL) -d $(TARGET_DIR)/var/www/x
	$(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
	$(INSTALL) -D -m 0644 $(THINGINO_SNMPD_PKGDIR)/files/www/config-snmpd.html \
		$(TARGET_DIR)/var/www/config-snmpd.html
	$(INSTALL) -D -m 0644 $(THINGINO_SNMPD_PKGDIR)/files/www/a/config-snmpd.js \
		$(TARGET_DIR)/var/www/a/config-snmpd.js
	$(INSTALL) -D -m 0755 $(THINGINO_SNMPD_PKGDIR)/files/www/x/json-config-snmpd.cgi \
		$(TARGET_DIR)/var/www/x/json-config-snmpd.cgi
	$(INSTALL) -D -m 0644 $(THINGINO_SNMPD_PKGDIR)/files/thingino-snmpd.webui.json \
		$(TARGET_DIR)/var/www/a/plugins/thingino-snmpd.webui.json
endef
endif

define THINGINO_SNMPD_INSTALL_THINGINO_FILES
	# Stage defaults for later merge by thingino-core
	$(INSTALL) -D -m 0644 $(THINGINO_SNMPD_PKGDIR)/files/thingino-snmpd.json \
		$(TARGET_DIR)/usr/share/thingino-defaults/50-snmpd.json

	# The init script bails out unless snmpd.enabled is true, and that
	# flag ships as false, so the daemon stays off until configured.
	$(INSTALL) -D -m 0755 $(THINGINO_SNMPD_PKGDIR)/files/S60snmpd \
		$(TARGET_DIR)/etc/init.d/S60snmpd

	$(THINGINO_SNMPD_INSTALL_WWW_CMDS)
endef

THINGINO_SNMPD_POST_INSTALL_TARGET_HOOKS += THINGINO_SNMPD_INSTALL_THINGINO_FILES

$(eval $(autotools-package))
