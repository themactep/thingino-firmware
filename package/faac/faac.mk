FAAC_SITE_METHOD = git
FAAC_SITE = https://github.com/knik0/faac
FAAC_SITE_BRANCH = master
FAAC_VERSION = b92b7f81e53b1027107c900b11609abf32a1fb1a

FAAC_LICENSE = MPEG-4-Reference-Code, LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_INSTALL_STAGING = YES

# Upstream builds with meson and generates config.h, faac.pc and the
# versioned shared lib (libfaac.so.1) itself. The CLI frontend is only
# built and installed when BR2_PACKAGE_FAAC_INSTALL_BIN is enabled.
FAAC_CONF_OPTS = \
	-Dfrontend=$(if $(BR2_PACKAGE_FAAC_INSTALL_BIN),true,false) \
	-Dmax-channels=2

$(eval $(meson-package))
