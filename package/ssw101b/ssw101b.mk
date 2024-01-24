################################################################################
#
# ssw101b
#
################################################################################

SSW101B_OPENIPC_SITE_METHOD = git
SSW101B_OPENIPC_SITE = https://github.com/openipc/ssw101b
SSW101B_OPENIPC_VERSION = $(shell git ls-remote $(SSW101B_OPENIPC_SITE) HEAD | head -1 | cut -f1)

SSW101B_LICENSE = GPL-2.0

$(eval $(kernel-module))
$(eval $(generic-package))
