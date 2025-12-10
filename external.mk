$(info --- FILE: external.mk)

ifneq ($(BR2_SOC_INGENIC_DUMMY),y)
# include makefiles from packages
include $(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk))
endif
