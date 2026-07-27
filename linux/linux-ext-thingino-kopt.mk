LINUX_EXTENSIONS += thingino-kopt

# Mappings for DTS configurations
# Format: CONFIG_SUFFIX|CAMERA_MODEL|DESTINATION_FILE
THINGINO_DTS_MAPPINGS = \
	WYZEC3P|wyze_cam3pro_t40xp|shark \
	A1_SMART_NVR|smart_nvr_a1n_eth|tucana

define THINGINO_KOPT_PREPARE_KERNEL
	$(foreach mapping,$(THINGINO_DTS_MAPPINGS),\
		$(if $(BR2_LINUX_KERNEL_EXT_THINGINO_KOPT_DTS_$(word 1,$(subst |, ,$(mapping)))),\
			$(INSTALL) -D -m 0644 \
				$(BR2_EXTERNAL_THINGINO_PATH)/board/ingenic/dts/$(word 2,$(subst |, ,$(mapping))).dts \
				$(LINUX_DIR)/arch/mips/boot/dts/ingenic/$(word 3,$(subst |, ,$(mapping))).dts ; \
		)\
	)
endef
