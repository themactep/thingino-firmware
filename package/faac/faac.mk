FAAC_SITE_METHOD = git
FAAC_SITE = https://github.com/knik0/faac
FAAC_SITE_BRANCH = master
FAAC_VERSION = 19504462aef3d444aa09b9cfcad0e2146889fb3b

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
