# Ingenic T31 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t31l t31lc t31n t31x t31a t31al t31zl t31zx),)

# what's common
SOC_FAMILY    := t31
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

# what's different
ifeq ($(SOC_MODEL),t31l)
SOC_RAM_MB    := 64
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31_sfcnand_lite,isvp_t31l_sfcnor)
else ifeq ($(SOC_MODEL),t31lc)
SOC_RAM_MB    := 64
SOC_UBOOT     := isvp_t31lc_sfcnor
else ifeq ($(SOC_MODEL),t31n)
SOC_RAM_MB    := 64
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31_sfcnand,isvp_t31n_sfcnor)
else ifeq ($(SOC_MODEL),t31x)
SOC_RAM_MB    := 128
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31_sfcnand_ddr128M,isvp_t31x_sfcnor)
else ifeq ($(SOC_MODEL),t31a)
SOC_RAM_MB    := 128
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31a_sfcnand_ddr128M,isvp_t31a_sfcnor)
else ifeq ($(SOC_MODEL),t31al)
SOC_RAM_MB    := 128
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31al_sfcnand_ddr128M,isvp_t31x_sfcnor)
else ifeq ($(SOC_MODEL),t31zl)
SOC_RAM_MB    := 64
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31_sfcnand_lite,isvp_t31n_sfcnor)
else
SOC_RAM_MB    := 128
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31_sfcnand_ddr128M,isvp_t31x_sfcnor)
endif

endif
