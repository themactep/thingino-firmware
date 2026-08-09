# Ingenic T20 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t20l t20n t20x t20z),)

SOC_FAMILY    := t20
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t20l)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t20l_sfcnor
endif

ifeq ($(SOC_MODEL),t20n)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t20n_sfcnor
endif

ifeq ($(SOC_MODEL),t20x)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t20x_sfcnor
endif

ifeq ($(SOC_MODEL),t20z)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t20n_sfcnor
endif

endif
