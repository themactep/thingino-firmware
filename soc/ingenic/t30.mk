# Ingenic T30 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t30l t30n t30x t30a),)

SOC_FAMILY    := t30
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t30l)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t30l_sfcnor
endif

ifeq ($(SOC_MODEL),t30n)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t30n_sfcnor
endif

ifeq ($(SOC_MODEL),t30x)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t30x_sfcnor
endif

ifeq ($(SOC_MODEL),t30a)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t30a_sfcnor
endif

endif
