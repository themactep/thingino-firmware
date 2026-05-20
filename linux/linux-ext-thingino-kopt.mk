LINUX_EXTENSIONS += thingino-kopt

# Mappings for DTS configurations
# Format: CONFIG_SUFFIX|CAMERA_MODEL|DESTINATION_FILE
THINGINO_DTS_MAPPINGS = \
	WYZEC3P|wyze_cam3pro_t40xp|shark \
	EUFYT8416|eufy_t8416_t40xp|shark \
	A1_SMART_NVR|smart_nvr_a1n_eth|tucana \
        IGETC5PT|iget_c5pt_t41lq|marmot \
        WYZEV4|wyze_cam4_t41nq|marmot \
        WYZEPANV4|wyze_panv4_t32nq|goat

THINGINO_LED_CONFIG = $(BR2_CONFIG)
THINGINO_LED_HEADER = $(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/chip-$(SOC_FAMILY)/isvp/common/thingino_leds.h
THINGINO_LED_BOARD_BASE = $(LINUX_DIR)/arch/mips/xburst/soc-$(SOC_FAMILY)/chip-$(SOC_FAMILY)/isvp/common/board_base.c

define THINGINO_KOPT_PREPARE_KERNEL
	sh $(BR2_EXTERNAL_THINGINO_PATH)/scripts/generate_kernel_led_header.sh \
		$(THINGINO_LED_CONFIG) \
		$(THINGINO_LED_HEADER)
	sh $(BR2_EXTERNAL_THINGINO_PATH)/scripts/patch_kernel_leds_board_base.sh \
		$(THINGINO_LED_BOARD_BASE)
	$(foreach mapping,$(THINGINO_DTS_MAPPINGS),\
		$(if $(BR2_LINUX_KERNEL_EXT_THINGINO_KOPT_DTS_$(word 1,$(subst |, ,$(mapping)))),\
			$(INSTALL) -D -m 0644 \
				$(BR2_EXTERNAL_THINGINO_PATH)/board/ingenic/dts/$(word 2,$(subst |, ,$(mapping))).dts \
				$(LINUX_DIR)/arch/mips/boot/dts/ingenic/$(word 3,$(subst |, ,$(mapping))).dts ; \
		)\
	)
endef
