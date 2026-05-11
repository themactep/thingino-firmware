PRYNTU_VERSION = c-rewrite
PRYNTU_SITE = https://github.com/themactep/pryntu
PRYNTU_SITE_METHOD = git

PRYNTU_DEPENDENCIES += host-cmake
PRYNTU_DEPENDENCIES += ingenic-lib

ifeq ($(BR2_TOOLCHAIN_USES_MUSL),y)
PRYNTU_DEPENDENCIES += ingenic-musl
endif

ifeq ($(BR2_TOOLCHAIN_USES_UCLIBC),y)
PRYNTU_DEPENDENCIES += ingenic-uclibc
endif

PRYNTU_CONF_OPTS += -DPRYNTU_BUILD_TESTS=ON
ifeq ($(BR2_PACKAGE_PRYNTU_CONTROL_API),y)
PRYNTU_CONF_OPTS += -DPRYNTU_BUILD_CONTROL_API=ON
else
PRYNTU_CONF_OPTS += -DPRYNTU_BUILD_CONTROL_API=OFF
endif

define PRYNTU_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/pryntud $(TARGET_DIR)/usr/bin/pryntud
	$(if $(filter y,$(BR2_PACKAGE_PRYNTU_CONTROL_API)),$(INSTALL) -D -m 0755 $(@D)/pryntuctl $(TARGET_DIR)/usr/bin/pryntuctl)
	$(INSTALL) -D -m 0755 $(PRYNTU_PKGDIR)/files/S31pryntu $(TARGET_DIR)/etc/init.d/S31pryntu
	$(INSTALL) -D -m 0644 $(PRYNTU_PKGDIR)/files/pryntu.conf $(TARGET_DIR)/etc/pryntu.conf
	$(INSTALL) -D -m 0644 $(PRYNTU_PKGDIR)/files/pryntu.json $(TARGET_DIR)/etc/pryntu.json
endef

$(eval $(cmake-package))
