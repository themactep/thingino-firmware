################################################################################
#
# quirc-openipc
#
################################################################################

ifeq ($(LOCAL_DOWNLOAD),y)
QUIRC_OPENIPC_SITE_METHOD = git
QUIRC_OPENIPC_SITE = https://github.com/openipc/quirc
QUIRC_OPENIPC_VERSION = $(shell git ls-remote $(QUIRC_OPENIPC_SITE) HEAD | head -1 | cut -f1)
else
QUIRC_OPENIPC_SITE = https://github.com/openipc/quirc/archive
QUIRC_OPENIPC_SOURCE = master.tar.gz
endif

QUIRC_OPENIPC_DEPENDENCIES += libjpeg
QUIRC_OPENIPC_LICENSE = ISC
QUIRC_OPENIPC_LICENSE_FILES = LICENSE.txt

QUIRC_OPENIPC_MAKE_OPTS = \
	CC=$(TARGET_CC) \
	AR=$(TARGET_AR) \
	LDFLAGS="-s"

define QUIRC_OPENIPC_BUILD_CMDS
	$(MAKE) $(QUIRC_OPENIPC_MAKE_OPTS) -C $(@D) all
endef

define QUIRC_OPENIPC_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/bin
	$(INSTALL) -m 755 -t $(TARGET_DIR)/usr/bin $(@D)/qrscan
endef

$(eval $(generic-package))
