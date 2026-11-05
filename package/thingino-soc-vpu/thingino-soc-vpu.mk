################################################################################
#
# thingino-soc-vpu - vendor T20 soc_vpu (Helix) video encoder driver
#
################################################################################

THINGINO_SOC_VPU_VERSION = 1.0
THINGINO_SOC_VPU_SITE = $(THINGINO_SOC_VPU_PKGDIR)/src
THINGINO_SOC_VPU_SITE_METHOD = local
# Ingenic SDK driver, redistributed under the SDK licence.
THINGINO_SOC_VPU_LICENSE = Ingenic SDK
THINGINO_SOC_VPU_DEPENDENCIES = linux

THINGINO_SOC_VPU_MODULE_SUBDIRS = .
THINGINO_SOC_VPU_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	DIR=.

ifeq ($(BR2_THINGINO_DEV_CAMERA),y)
define THINGINO_SOC_VPU_INSTALL_LOADER
	$(INSTALL) -d $(TARGET_DIR)/etc/modules.d
	echo "soc-vpu" > $(TARGET_DIR)/etc/modules.d/10-soc-vpu
endef
THINGINO_SOC_VPU_POST_INSTALL_TARGET_HOOKS += THINGINO_SOC_VPU_INSTALL_LOADER
endif

$(eval $(kernel-module))
$(eval $(generic-package))
