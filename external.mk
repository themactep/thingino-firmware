ifneq ($(BR2_SOC_INGENIC_DUMMY),y)
# Include makefiles from packages. The *-override.mk fragments are pulled in
# through BR2_PACKAGE_OVERRIDE_FILE (thingino-overrides.mk); excluding them
# here keeps them from being applied twice.
include $(filter-out %-override.mk,$(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk)))

# The pinned buildroot lacks BUSYBOX_KCONFIG_DEPENDENCIES += toolchain, so
# busybox's kconfig step can race the toolchain under -j. GNU make merges
# prerequisites across rules, so this adds the same order-only dependency
# without patching the submodule.
$(BUSYBOX_DIR)/.stamp_dotconfig: | toolchain
endif
