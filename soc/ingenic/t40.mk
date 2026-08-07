# Ingenic T40 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t40n t40nn t40xp t40a),)

SOC_FAMILY    := t40
SOC_ARCH      := xburst2

ifeq ($(SOC_MODEL),t40n)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t40n_sfcnor
SOC_UBOOT_NAND := isvp_t40n_sfcnand
endif

ifeq ($(SOC_MODEL),t40nn)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t40n_sfcnor
SOC_UBOOT_NAND := isvp_t40n_sfcnand
endif

ifeq ($(SOC_MODEL),t40xp)
SOC_RAM_MB     := 256
SOC_UBOOT_NOR  := isvp_t40xp_sfcnor
SOC_UBOOT_NAND := isvp_t40xp_sfcnand
endif

ifeq ($(SOC_MODEL),t40a)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t40n_sfcnor
SOC_UBOOT_NAND := isvp_t40a_sfcnand
endif

endif
