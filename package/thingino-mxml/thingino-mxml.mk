################################################################################
#
# thingino-mxml
#
################################################################################

THINGINO_MXML_VERSION = 4.0.4
THINGINO_MXML_SITE = https://github.com/michaelrsweet/mxml/releases/download/v$(THINGINO_MXML_VERSION)
THINGINO_MXML_SOURCE = mxml-$(THINGINO_MXML_VERSION).tar.gz
THINGINO_MXML_LICENSE = Apache-2.0 with exceptions
THINGINO_MXML_LICENSE_FILES = LICENSE
THINGINO_MXML_INSTALL_STAGING = YES

# mxml uses autotools-like configure script
define THINGINO_MXML_CONFIGURE_CMDS
	cd $(@D) && \
	$(TARGET_CONFIGURE_OPTS) \
	./configure \
		--host=$(GNU_TARGET_NAME) \
		--build=$(GNU_HOST_NAME) \
		--prefix=/usr \
		--disable-shared \
		--enable-static
endef

define THINGINO_MXML_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) libmxml.a
endef

define THINGINO_MXML_INSTALL_STAGING_CMDS
	$(INSTALL) -D -m 0644 $(@D)/libmxml.a $(STAGING_DIR)/usr/lib/libmxml.a
	$(INSTALL) -D -m 0644 $(@D)/mxml.h $(STAGING_DIR)/usr/include/mxml.h
endef

# No target installation needed for static library
define THINGINO_MXML_INSTALL_TARGET_CMDS
	# Static library only, no target installation needed
endef

$(eval $(generic-package))
