################################################################################
#
# uqmi-openipc
#
################################################################################

UQMI_OPENIPC_SITE_METHOD = git
UQMI_OPENIPC_SITE = git://git.openwrt.org/project/uqmi
UQMI_OPENIPC_VERSION = f254fc59c710d781eca3ec36e0bff2d8970370fa
#UQMI_OPENIPC_VERSION = $(shell git ls-remote $(UQMI_OPENIPC_SITE) HEAD | head -1 | awk '{ print $$1 }')

UQMI_OPENIPC_DEPENDENCIES = json-c-openipc libubox
UQMI_OPENIPC_LICENSE = LGPL-2.0+
UQMI_OPENIPC_LICENSE_FILES = COPYING

$(eval $(cmake-package))
