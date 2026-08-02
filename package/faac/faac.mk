FAAC_VERSION = 2.0
FAAC_SITE = $(call github,knik0,faac,faac-$(FAAC_VERSION))

FAAC_LICENSE = MPEG-4-Reference-Code, LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_INSTALL_STAGING = YES
FAAC_INSTALL_TARGET = YES

FAAC_CFLAGS = $(TARGET_CFLAGS) -ffast-math

FAAC_CONF_OPTS = \
	-Dmax-channels=2

ifeq ($(BR2_PACKAGE_FAAC_INSTALL_BIN),y)
FAAC_CONF_OPTS += -Dfrontend=true
else
FAAC_CONF_OPTS += -Dfrontend=false
endif

$(eval $(meson-package))
