LINUX_EXTENSIONS += thingino-kopt

# Mappings for DTS configurations
# Format: CONFIG_SUFFIX|CAMERA_MODEL|DESTINATION_FILE
THINGINO_DTS_MAPPINGS = \
	WYZEC3P|wyze_cam3pro_t40xp|shark \
	A1_SMART_NVR|smart_nvr_a1n_eth|tucana \
        IGETC5PT|iget_c5pt_t41lq|marmot

define THINGINO_KOPT_PREPARE_KERNEL
	$(foreach mapping,$(THINGINO_DTS_MAPPINGS),\
		$(if $(BR2_LINUX_KERNEL_EXT_THINGINO_KOPT_DTS_$(word 1,$(subst |, ,$(mapping)))),\
			$(INSTALL) -D -m 0644 \
				$(BR2_EXTERNAL_THINGINO_PATH)/board/ingenic/dts/$(word 2,$(subst |, ,$(mapping))).dts \
				$(LINUX_DIR)/arch/mips/boot/dts/ingenic/$(word 3,$(subst |, ,$(mapping))).dts ; \
		)\
	)
	@set -e; \
	camera="$(CAMERA)"; \
	test -n "$$camera" || exit 0; \
	camera_dir="$(BR2_EXTERNAL_THINGINO_PATH)/configs/cameras/$$camera"; \
	if [ ! -d "$$camera_dir" ]; then \
		camera_dir="$(BR2_EXTERNAL_THINGINO_PATH)/configs/cameras-exp/$$camera"; \
	fi; \
	led_dtsi="$$camera_dir/leds.dtsi"; \
	test -f "$$led_dtsi" || exit 0; \
	map_file="$(BR2_EXTERNAL_THINGINO_PATH)/configs/camera-kernel-dts.map"; \
	base_dts="$$(sed -n "s/^$${camera}=\([^ #]*\).*/\1/p" "$$map_file" | head -n1)"; \
	test -n "$$base_dts"; \
	kernel_dts_dir="$(LINUX_DIR)/arch/mips/boot/dts/ingenic"; \
	target_dts="$$kernel_dts_dir/$$base_dts.dts"; \
	test -f "$$target_dts"; \
	camera_dtsi="thingino-leds-$${camera}.dtsi"; \
	$(INSTALL) -D -m 0644 "$$led_dtsi" "$$kernel_dts_dir/$$camera_dtsi"; \
	include_line="/include/ \"$$camera_dtsi\""; \
	grep -Fqx "$$include_line" "$$target_dts" || { \
		tmp_file="$$(mktemp)"; \
		printf '%s\n' "$$include_line" >"$$tmp_file"; \
		cat "$$target_dts" >>"$$tmp_file"; \
		mv "$$tmp_file" "$$target_dts"; \
	}
endef
