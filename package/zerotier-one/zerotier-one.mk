ZEROTIER_ONE_VERSION = 1.16.0
ZEROTIER_ONE_SITE = $(call github,zerotier,ZeroTierOne,$(ZEROTIER_ONE_VERSION))

ZEROTIER_ONE_LICENSE = BUSL-1.1
ZEROTIER_ONE_LICENSE_FILES = LICENSE.txt

ZEROTIER_ONE_MAKE_OPTS = ZT_SSO_SUPPORTED=0 \
	CC="$(TARGET_CC)" \
	CXX="$(TARGET_CXX)" \
	FLOATABI="$(BR2_GCC_TARGET_FLOAT_ABI)" \
	LDFLAGS="$(TARGET_LDFLAGS)"

ZEROTIER_ONE_DEPENDENCIES = \
	libminiupnpc \
	libnatpmp

define ZEROTIER_ONE_LINUX_CONFIG_FIXUPS
	$(call KCONFIG_SET_OPT,CONFIG_TUN,m)
endef

define ZEROTIER_ONE_BUILD_CMDS
	$(MAKE) $(ZEROTIER_ONE_MAKE_OPTS) -C $(@D) all
endef

define ZEROTIER_ONE_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) install

	$(INSTALL) -D -m 0644 $(ZEROTIER_ONE_PKGDIR)/files/zerotier.json \
		$(TARGET_DIR)/etc/zerotier.json
	$(INSTALL) -D -m 0755 $(ZEROTIER_ONE_PKGDIR)/files/S90zerotier \
		$(TARGET_DIR)/etc/init.d/S90zerotier
	$(INSTALL) -D -m 0644 $(ZEROTIER_ONE_PKGDIR)/files/zerotiervpnisdown.opus \
		$(TARGET_DIR)/usr/share/sounds/zerotiervpnisdown.opus
	$(INSTALL) -D -m 0644 $(ZEROTIER_ONE_PKGDIR)/files/zerotiervpnisup.opus \
		$(TARGET_DIR)/usr/share/sounds/zerotiervpnisup.opus
endef

$(eval $(generic-package))
