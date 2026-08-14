ifneq ($(BR2_SOC_INGENIC_DUMMY),y)
# Include makefiles from packages. The *-override.mk fragments are pulled in
# through BR2_PACKAGE_OVERRIDE_FILE (thingino-overrides.mk); excluding them
# here keeps them from being applied twice.
include $(filter-out %-override.mk,$(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk)))
endif
