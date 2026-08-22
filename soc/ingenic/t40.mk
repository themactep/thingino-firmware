# Ingenic T40 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t40n t40nn t40xp t40a),)

# what's common
SOC_ARCH   := xburst2
SOC_FAMILY := t40

# what's different
ifeq ($(SOC_MODEL),t40xp)
SOC_RAM_MB := 256
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t40xp_sfcnand,isvp_t40xp_sfcnor)
else ifeq ($(SOC_MODEL),t40a)
SOC_RAM_MB := 128
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t40a_sfcnand,isvp_t40n_sfcnor)
else
SOC_RAM_MB := 128
SOC_UBOOT  := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t40n_sfcnand,isvp_t40n_sfcnor)
endif

endif
