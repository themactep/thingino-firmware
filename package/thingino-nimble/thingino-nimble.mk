THINGINO_NIMBLE_SITE_METHOD = git
THINGINO_NIMBLE_SITE = https://github.com/gtxaspec/atbm-wifi
THINGINO_NIMBLE_SITE_BRANCH = master
THINGINO_NIMBLE_VERSION = 13953b6e9090e620640edf4c6ea8ffc2e46da6b4

THINGINO_NIMBLE_LICENSE = Apache-2.0
THINGINO_NIMBLE_LICENSE_FILES = LICENSE

# Install library and headers for libblepp
THINGINO_NIMBLE_INSTALL_STAGING = YES
THINGINO_NIMBLE_INSTALL_TARGET = YES

THINGINO_NIMBLE_DEPENDENCIES = host-pkgconf

# Copy our custom Makefile and OS files to the build directory
define THINGINO_NIMBLE_CONFIGURE_CMDS
	cp -f $(THINGINO_NIMBLE_PKGDIR)/Makefile.nimble $(@D)/Makefile
	cp -rf $(THINGINO_NIMBLE_PKGDIR)/os $(@D)/
endef

define THINGINO_NIMBLE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		CC="$(TARGET_CC)" \
		LD=$(TARGET_CC) \
		CROSS_COMPILE="$(TARGET_CROSS)" \
		all
endef

define THINGINO_NIMBLE_INSTALL_STAGING_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		DESTDIR="$(STAGING_DIR)" \
		install-staging
endef

define THINGINO_NIMBLE_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) \
		DESTDIR="$(TARGET_DIR)" \
		install-target
endef


$(eval $(generic-package))