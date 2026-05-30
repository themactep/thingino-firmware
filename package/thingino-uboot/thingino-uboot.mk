################################################################################
#
# Thingino integration hooks for Buildroot's U-Boot package
#
################################################################################

ifeq ($(BR2_TARGET_UBOOT)$(BR_BUILDING),yy)

UBOOT_DEPENDENCIES += host-libyaml host-uboot-tools
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
		KERNEL_OFFSET=$$(( $(CONFIG_OFFSET) + $(CONFIG_PARTITION_SIZE) )); \
		ROOTFS_OFFSET=$$(( $$KERNEL_OFFSET + $$KERNEL_SIZE_ALIGNED )); \
		KERNEL_OFFSET_HEX=$$(printf '0x%x' $$KERNEL_OFFSET); \
		KERNEL_OFFSET_KB=$$(( $$KERNEL_OFFSET / 1024 )); \
		FLASH_SIZE_BYTES=$$(( $(FLASH_SIZE_MB) * 1024 * 1024 )); \
		FLASH_SIZE_KB=$$(( $(FLASH_SIZE_MB) * 1024 )); \
		UPGRADE_SIZE_KB=$$(( $$FLASH_SIZE_KB - $$KERNEL_OFFSET_KB )); \
		MTDPARTS="$(THINGINO_UBOOT_FLASH_CONTROLLER):$(U_BOOT_SIZE_KB)k(boot),$(UB_ENV_SIZE_KB)k(env),$(CONFIG_SIZE_KB)k(config),$${KERNEL_SIZE_KB}k(kernel),$${ROOTFS_SIZE_KB}k(rootfs),$${UPGRADE_SIZE_KB}k@$${KERNEL_OFFSET_HEX}(upgrade),$${FLASH_SIZE_KB}k@0(all)"; \
		echo "Compiling U-Boot with mtdparts=$$MTDPARTS"; \
		sed -i "s|CONFIG_MTDPARTS_DEFAULT=.*|CONFIG_MTDPARTS_DEFAULT=\"$$MTDPARTS\"|" $(@D)/include/configs/isvp_common.h; \
		$(BR2_EXTERNAL_THINGINO_PATH)/scripts/uboot-device-env.sh $(THINGINO_UENV_TXT) \
			$(@D)/include/configs/isvp_common.h; \
	fi
endef
UBOOT_PRE_BUILD_HOOKS += THINGINO_PATCH_DEV_ENV

endif
