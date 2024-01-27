################################################################################
#
# ingenic-opensdk
#
################################################################################

INGENIC_OPENSDK_SITE_METHOD = git
INGENIC_OPENSDK_SITE = https://github.com/themactep/openingenic.git
#INGENIC_OPENSDK_SITE = https://github.com/OpenIPC/openingenic
INGENIC_OPENSDK_VERSION = $(shell git ls-remote $(INGENIC_OPENSDK_SITE) HEAD | head -1 | cut -f1)

INGENIC_OPENSDK_LICENSE = GPL-3.0
INGENIC_OPENSDK_LICENSE_FILES = LICENSE

ifeq ($(SOC_FAMILY),)
$(error SOC_FAMILY missing)
endif

INGENIC_OPENSDK_MODULE_SUBDIRS = kernel
INGENIC_OPENSDK_MODULE_MAKE_OPTS = \
	SOC_FAMILY=$(SOC_FAMILY) \
	SENSOR_MODEL=$(BR2_SENSOR_MODEL) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic

$(eval $(kernel-module))
$(eval $(generic-package))
