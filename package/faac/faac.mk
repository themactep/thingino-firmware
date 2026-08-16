FAAC_SITE_METHOD = git
FAAC_SITE = https://github.com/knik0/faac
FAAC_SITE_BRANCH = master
FAAC_VERSION = 9392e861480c9845a92e7591349b4f9a90a65c1a

FAAC_LICENSE = MPEG-4-Reference-Code, LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_INSTALL_STAGING = YES

# Upstream builds with meson and generates config.h, faac.pc and the
# versioned shared lib (libfaac.so.1) itself. The CLI frontend is only
# built and installed when BR2_PACKAGE_FAAC_INSTALL_BIN is enabled.
FAAC_CONF_OPTS = \
	-Dfrontend=$(if $(BR2_PACKAGE_FAAC_INSTALL_BIN),true,false) \
	-Dmax-channels=2 \
	-Dsbr-decimation=4

$(eval $(meson-package))
