# Ingenic T23 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t23n t23dl t23zn),)

SOC_FAMILY    := t23
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t23n)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t23n_sfcnor
endif

ifeq ($(SOC_MODEL),t23dl)
SOC_RAM_MB     := 32
SOC_UBOOT_NOR  := isvp_t23dl_sfcnor
endif

ifeq ($(SOC_MODEL),t23zn)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t23zn_sfcnor
endif

endif
