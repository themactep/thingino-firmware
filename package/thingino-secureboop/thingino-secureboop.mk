ifeq ($(BR2_TARGET_UBOOT)$(BR2_PACKAGE_THINGINO_SECUREBOOP)$(BR_BUILDING),yyy)

SECUREBOOP_DIR = $(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-secureboop

define THINGINO_SECUREBOOP_INIT_TABLE_BYPASS
	@_bin=$$(ls $(@D)/u-boot-with-tpl-mmc-lzma.bin $(@D)/u-boot-with-spl-mmc-lzma.bin $(@D)/u-boot-with-tpl-lzma.bin $(@D)/u-boot-with-spl-lzma.bin $(@D)/u-boot-lzo-with-spl.bin 2>/dev/null | head -1); \
	if [ -z "$$_bin" ]; then \
		echo "SECUREBOOP: no U-Boot binary found in $(@D)"; exit 1; \
	fi; \
	_boot_off=0; \
	if [ "$$(xxd -l 4 -p $$_bin)" = "00000000" ]; then \
		_boot_off=0x4400; \
	fi; \
	echo "SECUREBOOP: injecting $(SOC_FAMILY) init-table patch ($$(basename $$_bin), boot_offset=$$_boot_off)"; \
	python3 $(SECUREBOOP_DIR)/ingenic_bootrom_patcher.py \
		--soc $(SOC_FAMILY) \
		$(if $(filter t40 t41 a1,$(SOC_FAMILY)),--no-header-check) \
		$(if $(BR2_PACKAGE_THINGINO_KOPT_MMC0_BOOT),--sd) \
		--boot-offset $$_boot_off \
		-o "$$_bin" "$$_bin" \
	|| { echo "SECUREBOOP: $(SOC_FAMILY) patch FAILED"; exit 1; }; \
	echo "SECUREBOOP: $(SOC_FAMILY) patch OK"
endef

SECUREBOOP_T31_MODULUS = $(call qstrip,$(BR2_PACKAGE_THINGINO_SECUREBOOP_T31_MODULUS))
SECUREBOOP_T31_EXPONENT = $(call qstrip,$(BR2_PACKAGE_THINGINO_SECUREBOOP_T31_EXPONENT))

define THINGINO_SECUREBOOP_T31_PATCH
	@_bin=$$(ls $(@D)/u-boot-with-tpl-mmc-lzma.bin $(@D)/u-boot-with-spl-mmc-lzma.bin $(@D)/u-boot-with-tpl-lzma.bin $(@D)/u-boot-with-spl-lzma.bin $(@D)/u-boot-lzo-with-spl.bin 2>/dev/null | head -1); \
	if [ -z "$$_bin" ]; then \
		echo "SECUREBOOP: no U-Boot binary found in $(@D)"; exit 1; \
	fi; \
	if [ -z "$(SECUREBOOP_T31_MODULUS)" ]; then \
		echo "SECUREBOOP: T31 modulus not configured -- skipping"; \
		echo "  set BR2_PACKAGE_THINGINO_SECUREBOOP_T31_MODULUS in the defconfig"; \
	else \
		echo "SECUREBOOP: patching T31 SPL signature ($$(basename $$_bin))"; \
		python3 $(SECUREBOOP_DIR)/ingenic_t31_spl_patcher.py patch \
			--modulus "$(SECUREBOOP_T31_MODULUS)" \
			$(if $(filter-out 65537,$(SECUREBOOP_T31_EXPONENT)),-e $(SECUREBOOP_T31_EXPONENT)) \
			--in-place "$$_bin" \
		|| { echo "SECUREBOOP: T31 patch FAILED"; exit 1; }; \
		echo "SECUREBOOP: T31 patch OK"; \
	fi
endef

define THINGINO_SECUREBOOP_HOOK
	$(if $(filter t23 t32 t40 t41 a1,$(SOC_FAMILY)),$(THINGINO_SECUREBOOP_INIT_TABLE_BYPASS))
	$(if $(filter t31,$(SOC_FAMILY)),$(THINGINO_SECUREBOOP_T31_PATCH))
endef

UBOOT_POST_BUILD_HOOKS += THINGINO_SECUREBOOP_HOOK

endif
