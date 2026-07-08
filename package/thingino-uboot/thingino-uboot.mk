################################################################################
#
# Thingino integration hooks for Buildroot's U-Boot package
#
################################################################################

# Note: Dependencies (host-libyaml, host-uboot-tools) are NOT declared here
# because Buildroot parses external.mk before .config is loaded, so the
# ifeq guard below always fails on first parse. By the second parse
# (after .config) the package rules are already generated and the += is
# ignored. These deps are handled directly in the top-level Makefile:
#   - rebuild-% and rebuild-uboot targets list host-libyaml explicitly
#   - $(ROOTFS_BIN) target builds host-libyaml before pre-stamping uboot
ifeq ($(BR2_TARGET_UBOOT)$(BR_BUILDING),yy)
THINGINO_OUTPUT_DIR = $(if $(OUTPUT_DIR),$(OUTPUT_DIR),$(BASE_DIR))
THINGINO_BINARIES_DIR = $(if $(OUTPUT_DIR),$(OUTPUT_DIR)/images,$(BINARIES_DIR))
THINGINO_UENV_TXT = $(if $(U_BOOT_ENV_TXT),$(U_BOOT_ENV_TXT),$(THINGINO_OUTPUT_DIR)/uenv.txt)

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_ENABLE_BAR),y)
UBOOT_MAKE_OPTS += CONFIG_SPI_FLASH_BAR=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_EXTERNAL_ENV_ENABLE),y)
UBOOT_MAKE_OPTS += CONFIG_BOOTARGS_EXTERNAL=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_PHY_RESET_AFTER_CONFIG),y)
UBOOT_MAKE_OPTS += CONFIG_PHY_RESET_AFTER_CONFIG=1
UBOOT_MAKE_OPTS += CONFIG_GPIO_PHY_RESET=$(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_GPIO_PHY_RESET))
UBOOT_MAKE_OPTS += CONFIG_GPIO_PHY_RESET_ENLEVEL=$(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_GPIO_PHY_RESET_ENLEVEL))
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_JZ_SFC),y)
THINGINO_UBOOT_FLASH_CONTROLLER := jz_sfc
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC_NAND),y)
THINGINO_UBOOT_FLASH_CONTROLLER := sfc_nand
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC0_NOR),y)
THINGINO_UBOOT_FLASH_CONTROLLER := sfc0_nor
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC1_NOR),y)
THINGINO_UBOOT_FLASH_CONTROLLER := sfc1_nor
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC0_NAND),y)
THINGINO_UBOOT_FLASH_CONTROLLER := sfc0_nand
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC1_NAND),y)
THINGINO_UBOOT_FLASH_CONTROLLER := sfc1_nand
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_CUSTOM),y)
THINGINO_UBOOT_FLASH_CONTROLLER := $(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_CUSTOM_STRING)
else
THINGINO_UBOOT_FLASH_CONTROLLER := jz_sfc
endif

define THINGINO_UBOOT_COPY_SHA1_HEADER
	if [ -f $(@D)/include/sha1.h ]; then \
		cp $(@D)/include/sha1.h $(@D)/tools/sha1.h; \
	fi
endef
UBOOT_POST_PATCH_HOOKS += THINGINO_UBOOT_COPY_SHA1_HEADER

define THINGINO_UBOOT_RMEM_SET_VALUE
	if [ -n "$(ISP_RMEM_MB)" ]; then \
		if [ "$(SOC_FAMILY)" = "t20" -o "$(SOC_FAMILY)" = "t10" ]; then \
			osmem=$$(( $(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_ISPMEM_MB) )) && \
			ispmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_ISPMEM_MB)) * 0x100000 )) && \
			rmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB)) * 0x100000 )) && \
			grep -q "^osmem=$${osmem}M@0x0" $(THINGINO_UENV_TXT) || echo "osmem=$${osmem}M@0x0" >> $(THINGINO_UENV_TXT) && \
			grep -q "^ispmem=$(ISP_ISPMEM_MB)M@$$(printf '0x%x' $$ispmem_offset)" $(THINGINO_UENV_TXT) || echo "ispmem=$(ISP_ISPMEM_MB)M@$$(printf '0x%x' $$ispmem_offset)" >> $(THINGINO_UENV_TXT) && \
			grep -q "^rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" $(THINGINO_UENV_TXT) || echo "rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" >> $(THINGINO_UENV_TXT); \
		elif [ "$(SOC_FAMILY)" = "t40" -o "$(SOC_FAMILY)" = "t41" ]; then \
			osmem=$$(( $(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_NMEM_MB) )) && \
			rmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_NMEM_MB)) * 0x100000 )) && \
			nmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_NMEM_MB)) * 0x100000 )) && \
			grep -q "^osmem=$${osmem}M@0x0" $(THINGINO_UENV_TXT) || echo "osmem=$${osmem}M@0x0" >> $(THINGINO_UENV_TXT) && \
			grep -q "^rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" $(THINGINO_UENV_TXT) || echo "rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" >> $(THINGINO_UENV_TXT) && \
			grep -q "^nmem=$(ISP_NMEM_MB)M@$$(printf '0x%x' $$nmem_offset)" $(THINGINO_UENV_TXT) || echo "nmem=$(ISP_NMEM_MB)M@$$(printf '0x%x' $$nmem_offset)" >> $(THINGINO_UENV_TXT); \
		else \
			osmem=$$(( $(SOC_RAM_MB) - $(ISP_RMEM_MB) )) && \
			rmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB)) * 0x100000 )) && \
			grep -q "^osmem=$${osmem}M@0x0" $(THINGINO_UENV_TXT) || echo "osmem=$${osmem}M@0x0" >> $(THINGINO_UENV_TXT) && \
			grep -q "^rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" $(THINGINO_UENV_TXT) || echo "rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" >> $(THINGINO_UENV_TXT); \
		fi; \
	else \
		echo "No ISP_RMEM_MB value set"; \
	fi
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_UBOOT_RMEM_SET_VALUE

define THINGINO_GENERATE_UBOOT_ENV
	@touch $(THINGINO_UENV_TXT)
	@env BR2_PACKAGE_THINGINO_UBOOT_ROOT='$(value BR2_PACKAGE_THINGINO_UBOOT_ROOT)' sh -c 'grep -q "^root=" $(THINGINO_UENV_TXT) || echo "root=$$BR2_PACKAGE_THINGINO_UBOOT_ROOT" | sed "s/=\"/=/;s/\"$$//" >> $(THINGINO_UENV_TXT)'
	@env BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE='$(value BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE)' sh -c 'grep -q "^rootfstype=" $(THINGINO_UENV_TXT) || echo "rootfstype=$$BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE" | sed "s/=\"/=/;s/\"$$//" >> $(THINGINO_UENV_TXT)'
	@env BR2_PACKAGE_THINGINO_UBOOT_INIT='$(value BR2_PACKAGE_THINGINO_UBOOT_INIT)' sh -c 'grep -q "^init=" $(THINGINO_UENV_TXT) || echo "init=$$BR2_PACKAGE_THINGINO_UBOOT_INIT" | sed "s/=\"/=/;s/\"$$//" >> $(THINGINO_UENV_TXT)'
	@env BR2_PACKAGE_THINGINO_UBOOT_SD_ENABLE='$(BR2_PACKAGE_THINGINO_UBOOT_SD_ENABLE)' sh -c 'if [ "$$BR2_PACKAGE_THINGINO_UBOOT_SD_ENABLE" = "y" ]; then grep -q "^disable_sd=" $(THINGINO_UENV_TXT) && sed -i "s/^disable_sd=.*/disable_sd=false/" $(THINGINO_UENV_TXT) || echo "disable_sd=false" >> $(THINGINO_UENV_TXT); else grep -q "^disable_sd=" $(THINGINO_UENV_TXT) && sed -i "s/^disable_sd=.*/disable_sd=true/" $(THINGINO_UENV_TXT) || echo "disable_sd=true" >> $(THINGINO_UENV_TXT); fi'
	@env BR2_PACKAGE_THINGINO_UBOOT_ETH_ENABLE='$(BR2_PACKAGE_THINGINO_UBOOT_ETH_ENABLE)' sh -c 'if [ "$$BR2_PACKAGE_THINGINO_UBOOT_ETH_ENABLE" = "y" ]; then grep -q "^disable_eth=" $(THINGINO_UENV_TXT) && sed -i "s/^disable_eth=.*/disable_eth=false/" $(THINGINO_UENV_TXT) || echo "disable_eth=false" >> $(THINGINO_UENV_TXT); else grep -q "^disable_eth=" $(THINGINO_UENV_TXT) && sed -i "s/^disable_eth=.*/disable_eth=true/" $(THINGINO_UENV_TXT) || echo "disable_eth=true" >> $(THINGINO_UENV_TXT); fi'
	@sed -i "s|\$$(UBOOT_FLASH_CONTROLLER)|$(THINGINO_UBOOT_FLASH_CONTROLLER)|g" $(THINGINO_UENV_TXT)
	@sh -c '[ "$(SOC_FAMILY)" = "t40" -o "$(SOC_FAMILY)" = "t41" ] && sed -i "s|\$$(UBOOT_NMEM)|nmem=$$\{nmem\} |g" $(THINGINO_UENV_TXT) || sed -i "s|\$$(UBOOT_NMEM)||g" $(THINGINO_UENV_TXT)'
	@sh -c '[ "$(SOC_FAMILY)" = "t20" -o "$(SOC_FAMILY)" = "t10" ] && sed -i "s|\$$(UBOOT_ISPMEM)| ispmem=$$\{ispmem\} |g" $(THINGINO_UENV_TXT) || sed -i "s|\$$(UBOOT_ISPMEM)| |g" $(THINGINO_UENV_TXT)'
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_GENERATE_UBOOT_ENV

define THINGINO_PATCH_DEV_ENV
	@if [ -f $(@D)/include/configs/isvp_common.h ] && [ -f $(THINGINO_BINARIES_DIR)/uImage ] && [ -f $(THINGINO_BINARIES_DIR)/rootfs.squashfs ]; then \
		KERNEL_BIN_SIZE=$$(stat -c%s $(THINGINO_BINARIES_DIR)/uImage); \
		KERNEL_SIZE_ALIGNED=$$(( ($$KERNEL_BIN_SIZE + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK) )); \
		KERNEL_SIZE_KB=$$(( $$KERNEL_SIZE_ALIGNED / 1024 )); \
		ROOTFS_BIN_SIZE=$$(stat -c%s $(THINGINO_BINARIES_DIR)/rootfs.squashfs); \
		ROOTFS_SIZE_ALIGNED=$$(( ($$ROOTFS_BIN_SIZE + $(ALIGN_BLOCK) - 1) / $(ALIGN_BLOCK) * $(ALIGN_BLOCK) )); \
		ROOTFS_SIZE_KB=$$(( $$ROOTFS_SIZE_ALIGNED / 1024 )); \
		KERNEL_OFFSET=$$(( $(U_BOOT_PARTITION_SIZE) + $(UB_ENV_PARTITION_SIZE) )); \
		ROOTFS_OFFSET=$$(( $$KERNEL_OFFSET + $$KERNEL_SIZE_ALIGNED )); \
		ROOTFS_OFFSET_KB=$$(( $$ROOTFS_OFFSET / 1024 )); \
		FLASH_SIZE_KB=$$(( $(FLASH_SIZE_MB) * 1024 )); \
		DATA_SIZE_KB=$$(( $$FLASH_SIZE_KB - $$ROOTFS_OFFSET_KB - $$ROOTFS_SIZE_KB )); \
		DATA_OFFSET=$$(( $$ROOTFS_OFFSET + $$ROOTFS_SIZE_ALIGNED )); \
		MTDPARTS="$(THINGINO_UBOOT_FLASH_CONTROLLER):$(U_BOOT_SIZE_KB)k(boot),$(UB_ENV_SIZE_KB)k(env),$${KERNEL_SIZE_KB}k(kernel),$${ROOTFS_SIZE_KB}k(rootfs),$${DATA_SIZE_KB}k(data),$${FLASH_SIZE_KB}k@0(all)"; \
		echo "Compiling U-Boot with mtdparts=$$MTDPARTS"; \
		sed -i "s|CONFIG_MTDPARTS_DEFAULT=.*|CONFIG_MTDPARTS_DEFAULT=\"$$MTDPARTS\"|" $(@D)/include/configs/isvp_common.h; \
		$(BR2_EXTERNAL_THINGINO_PATH)/scripts/uboot-device-env.sh $(THINGINO_UENV_TXT) \
			$(@D)/include/configs/isvp_common.h; \
	fi
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_PATCH_DEV_ENV

# Drop the on-chip wired-Ethernet driver (DesignWare GMAC + PHY) when the board has no wired Ethernet.
ifneq ($(BR2_ETHERNET),y)
ifneq ($(BR2_THINGINO_UBOOT_VERSION_2013_07),y)
define THINGINO_UBOOT_DISABLE_WIRED_ETH
	$(call KCONFIG_DISABLE_OPT,CONFIG_ETH_DESIGNWARE_INGENIC,$(@D)/.config)
	$(call KCONFIG_DISABLE_OPT,CONFIG_ETH_DESIGNWARE,$(@D)/.config)
	$(call KCONFIG_DISABLE_OPT,CONFIG_PHY_ICPLUS,$(@D)/.config)
	$(UBOOT_KCONFIG_MAKE) olddefconfig
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_UBOOT_DISABLE_WIRED_ETH
endif
endif

# Drop the USB-Ethernet host drivers when the board has no USB OTG data port (no dongle possible).
ifneq ($(BR2_PACKAGE_THINGINO_KOPT_DWC2_OTG),y)
ifneq ($(BR2_THINGINO_UBOOT_VERSION_2013_07),y)
define THINGINO_UBOOT_DISABLE_USB_ETH
	$(call KCONFIG_DISABLE_OPT,CONFIG_USB_HOST_ETHER,$(@D)/.config)
	$(call KCONFIG_DISABLE_OPT,CONFIG_USB_ETHER_ASIX,$(@D)/.config)
	$(UBOOT_KCONFIG_MAKE) olddefconfig
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_UBOOT_DISABLE_USB_ETH
endif
endif

# Drop the audio/sound subsystem (disabling CONFIG_SOUND cascades I2S + codecs) when the board has no audio.
ifneq ($(BR2_THINGINO_AUDIO),y)
ifneq ($(BR2_THINGINO_UBOOT_VERSION_2013_07),y)
define THINGINO_UBOOT_DISABLE_AUDIO
	$(call KCONFIG_DISABLE_OPT,CONFIG_CMD_SOUND,$(@D)/.config)
	$(call KCONFIG_DISABLE_OPT,CONFIG_SOUND,$(@D)/.config)
	$(UBOOT_KCONFIG_MAKE) olddefconfig
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_UBOOT_DISABLE_AUDIO
endif
endif

# Inject this board's MMC card-detect + slot-power into the per-SoC U-Boot
# device tree from thingino.json (the GPIOs are board-specific, so they can't
# live in the shared .dts). The helper appends a vmmc-supply regulator and, on
# pull-up-capable SoCs, cd-gpios, to this board's build copy of the leaf .dts -
# so the mmc core powers and detects the slot natively, with no env gpio gate
# or power-up. The helper reads thingino.json with python3 (already a U-Boot
# build dependency via binman).
ifneq ($(BR2_THINGINO_UBOOT_VERSION_2013_07),y)
define THINGINO_UBOOT_INJECT_MMC_DT
	@DT=$$(sed -n 's/^CONFIG_DEFAULT_DEVICE_TREE="\(.*\)"/\1/p' $(@D)/.config); \
	[ -n "$$DT" ] && [ -f $(@D)/arch/mips/dts/$$DT.dts ] || exit 0; \
	$(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-uboot/inject-uboot-mmc-dt.sh \
		$(BR2_EXTERNAL_THINGINO_PATH)/$(CAMERA_SUBDIR)/$(CAMERA)/thingino.json \
		$(@D)/arch/mips/dts/$$DT.dts "$$DT"
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_UBOOT_INJECT_MMC_DT
endif

# On PTZ cameras with a GPIO/TCU stepper (BR2_THINGINO_MOTORS_TCU), the
# pan/tilt phase pins drive a coil array. From power-on until the Linux motor
# driver parks them they can hold a coil energised (the coils cook). Inject a
# gpio-hog per phase pin into this board's U-Boot leaf .dts (read from
# thingino.json, invert-aware park level) to hold them de-energised through the
# boot window, and enable CONFIG_GPIO_HOG so U-Boot acts on the hogs. SPI
# (ms419xx) and DW9714 focus units are not TCU, so they are skipped.
ifeq ($(BR2_THINGINO_MOTORS_TCU),y)
ifneq ($(BR2_THINGINO_UBOOT_VERSION_2013_07),y)
define THINGINO_UBOOT_INJECT_MOTOR_DT
	@DT=$$(sed -n 's/^CONFIG_DEFAULT_DEVICE_TREE="\(.*\)"/\1/p' $(@D)/.config); \
	[ -n "$$DT" ] && [ -f $(@D)/arch/mips/dts/$$DT.dts ] || exit 0; \
	$(BR2_EXTERNAL_THINGINO_PATH)/package/thingino-uboot/inject-uboot-motor-dt.sh \
		$(BR2_EXTERNAL_THINGINO_PATH)/$(CAMERA_SUBDIR)/$(CAMERA)/thingino.json \
		$(@D)/arch/mips/dts/$$DT.dts "$$DT"
	$(call KCONFIG_ENABLE_OPT,CONFIG_GPIO_HOG,$(@D)/.config)
	$(UBOOT_KCONFIG_MAKE) olddefconfig
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_UBOOT_INJECT_MOTOR_DT
endif
endif

endif
