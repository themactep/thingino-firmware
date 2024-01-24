################################################################################
#
# ssv6x5x-openipc
#
################################################################################

SSV6X5X_OPENIPC_SITE_METHOD = git
SSV6X5X_OPENIPC_SITE = https://github.com/openipc/ssv6x5x
SSV6X5X_OPENIPC_VERSION = $(shell git ls-remote $(SSV6X5X_OPENIPC_SITE) HEAD | head -1 | cut -f1)

SSV6X5X_OPENIPC_LICENSE = GPL-2.0
SSV6X5X_OPENIPC_LICENSE_FILES = COPYING

SSV6X5X_OPENIPC_MODULE_MAKE_OPTS = \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
