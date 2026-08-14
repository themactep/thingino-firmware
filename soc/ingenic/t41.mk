# Ingenic T41 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t41lq t41nq t41zl t41zn t41zx t41a),)

# what's common
SOC_ARCH   := xburst2
SOC_FAMILY := t41

# what's different
ifeq ($(SOC_MODEL),t41lq)
SOC_RAM_MB := 64
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t41lq_sfc0_nand,isvp_t41lq_sfcnor)
else ifeq ($(SOC_MODEL),t41zl)
SOC_RAM_MB := 64
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t41l_sfc0_nand,isvp_t41lq_sfcnor)
else ifeq ($(SOC_MODEL),t41nq)
SOC_RAM_MB := 128
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t41nq_sfc0_nand,isvp_t41nq_sfcnor)
else ifeq ($(SOC_MODEL),t41zn)
SOC_RAM_MB := 128
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t41n_sfc0_nand,isvp_t41nq_sfcnor)
else ifeq ($(SOC_MODEL),t41zx)
SOC_RAM_MB := 256
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t41zx_sfc0_nand,isvp_t41nq_sfcnor)
else
SOC_RAM_MB := 512
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t41a_sfc0_nand,isvp_t41nq_sfcnor)
endif

endif
