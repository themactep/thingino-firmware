# Ingenic T21 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t21l t21n t21x t21zn t21zl),)

SOC_FAMILY    := t21
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t21l)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t21n_sfcnor
endif

ifeq ($(SOC_MODEL),t21n)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t21n_sfcnor
endif

ifeq ($(SOC_MODEL),t21x)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t21n_sfcnor
endif

ifeq ($(SOC_MODEL),t21zn)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t21n_sfcnor
endif

ifeq ($(SOC_MODEL),t21zl)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t21n_sfcnor
endif

endif
