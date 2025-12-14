FAAC_SITE_METHOD = git
FAAC_SITE = https://github.com/knik0/faac
FAAC_SITE_BRANCH = master
FAAC_VERSION = 05f85a53d56f4c563524c5ffc2ebb2dd98fa7180

FAAC_LICENSE = MPEG-4-Reference-Code, LGPL-2.1+
FAAC_LICENSE_FILES = COPYING

FAAC_DEPENDENCIES = host-pkgconf

FAAC_INSTALL_STAGING = YES
FAAC_INSTALL_TARGET = YES

FAAC_CONF_OPTS = $(if $(BR2_PACKAGE_FAAC_ENABLE_DRM),-Denable_drm=true,-Denable_drm=false)

$(eval $(meson-package))
