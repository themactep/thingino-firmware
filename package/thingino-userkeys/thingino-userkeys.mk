THINGINO_USERKEYS_VERSION = 1.0
THINGINO_USERKEYS_SITE_METHOD = local
THINGINO_USERKEYS_SITE = $(THINGINO_USERKEYS_PKGDIR)/src
THINGINO_USERKEYS_MODULE_MAKE_OPTS = KSRC=$(LINUX_DIR)

TARGET_MODULES_PATH = $(TARGET_DIR)/usr/lib/modules/$(KERNEL_VERSION)$(call qstrip,$(LINUX_CONFIG_LOCALVERSION))
define THINGINO_USERKEYS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0644 $(@D)/gpio-userkeys.ko \
		$(TARGET_MODULES_PATH)/extra/gpio-userkeys.ko
endef

$(eval $(kernel-module))
$(eval $(generic-package))

# ingenic-sdk writes /etc/modules.d/gpio-userkeys from thingino.json at its own
# install step, which on a clean build runs before thingino.json exists, so the
# key module was never loaded. Regenerate it once the target tree is final.
ifeq ($(BR2_PACKAGE_THINGINO_USERKEYS),y)
TARGET_FINALIZE_HOOKS += GENERATE_GPIO_USERKEYS_CONFIG
endif
