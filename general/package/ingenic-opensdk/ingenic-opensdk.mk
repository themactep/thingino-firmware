################################################################################
#
# ingenic-opensdk
#
################################################################################

ifeq ($(LOCAL_DOWNLOAD),y)
#INGENIC_OPENSDK_SITE = https://github.com/themactep/openingenic
INGENIC_OPENSDK_SITE = file:///home/paul/localwork/openipc/openingenic-themactep/.git
INGENIC_OPENSDK_SITE_METHOD = git
INGENIC_OPENSDK_VERSION = $(shell git ls-remote $(INGENIC_OPENSDK_SITE) HEAD | head -1 | cut -f1)
else
INGENIC_OPENSDK_SITE = https://github.com/themactep/openingenic/archive
INGENIC_OPENSDK_SOURCE = master.tar.gz
endif

INGENIC_OPENSDK_LICENSE = GPL-3.0
INGENIC_OPENSDK_LICENSE_FILES = LICENSE

ifeq ($(OPENIPC_SOC_FAMILY),)
$(error OPENIPC_SOC_FAMILY missing)
endif

INGENIC_OPENSDK_MODULE_SUBDIRS = kernel
INGENIC_OPENSDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(OPENIPC_SOC_FAMILY) \
	SENSOR_MODEL=$(OPENIPC_SENSOR_MODEL) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic

$(eval $(kernel-module))
$(eval $(generic-package))
