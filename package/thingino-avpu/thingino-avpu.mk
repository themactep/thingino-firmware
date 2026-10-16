################################################################################
#
# thingino-avpu - vendor T31 AVPU (el150) video codec driver
#
################################################################################

THINGINO_AVPU_VERSION = 1.0
THINGINO_AVPU_SITE = $(THINGINO_AVPU_PKGDIR)/src
THINGINO_AVPU_SITE_METHOD = local
# Ingenic SDK driver, redistributed under the SDK licence.
THINGINO_AVPU_LICENSE = Ingenic SDK
THINGINO_AVPU_DEPENDENCIES = linux

# The sources only need the kernel headers (no SDK/SoC headers); the driver
# picks the T31 register/clock path from CONFIG_SOC_T31, which the 5.15 t31
# kernel sets.
THINGINO_AVPU_MODULE_SUBDIRS = .
THINGINO_AVPU_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	DIR=.

ifeq ($(BR2_THINGINO_DEV_CAMERA),y)
define THINGINO_AVPU_INSTALL_LOADER
	$(INSTALL) -d $(TARGET_DIR)/etc/modules.d
	echo "avpu $(AVPU_CLK_SRC) $(AVPU_CLK)" > $(TARGET_DIR)/etc/modules.d/10-avpu
endef
THINGINO_AVPU_POST_INSTALL_TARGET_HOOKS += THINGINO_AVPU_INSTALL_LOADER
endif

$(eval $(kernel-module))
$(eval $(generic-package))
