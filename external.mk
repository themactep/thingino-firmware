ifneq ($(BR2_SOC_INGENIC_DUMMY),y)
include $(sort $(wildcard $(BR2_EXTERNAL)/package/*/*.mk))
endif
