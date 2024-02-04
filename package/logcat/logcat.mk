################################################################################
#
# logcat
#
################################################################################

LOGCAT_SITE_METHOD = git
LOGCAT_SITE = https://github.com/gtxaspec/linux_logcat
LOGCAT_VERSION = $(shell git ls-remote $(LOGCAT_SITE) HEAD | head -1 | cut -f1)

LOGCAT_LICENSE = GPL-2.0
LOGCAT_LICENSE_FILES = COPYING

LOGCAT_INSTALL_STAGING = YES

$(eval $(cmake-package))
