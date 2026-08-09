# Ingenic T10 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t10l t10n t10a),)

SOC_FAMILY    := t10
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t10l)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t10l_sfcnor
endif

ifeq ($(SOC_MODEL),t10n)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t10n_sfcnor
endif

ifeq ($(SOC_MODEL),t10a)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t10n_sfcnor
endif

endif
