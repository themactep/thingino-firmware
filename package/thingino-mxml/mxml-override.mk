################################################################################
#
# mxml overrides for Thingino
#
################################################################################

ifeq ($(BR2_PACKAGE_THINGINO_MXML),y)

override MXML_VERSION = 4.0.4
override MXML_SITE = https://github.com/michaelrsweet/mxml/releases/download/v$(MXML_VERSION)
override MXML_SOURCE = mxml-$(MXML_VERSION).tar.gz

override MXML_CONF_OPTS += \
	--disable-shared \
	--enable-static

override MXML_INSTALL_TARGET = NO

endif
