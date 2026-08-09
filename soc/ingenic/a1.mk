# Ingenic A1 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),a1n a1nt a1x a1l a1a),)

SOC_FAMILY    := a1
SOC_ARCH      := xburst2

ifeq ($(SOC_MODEL),a1n)
SOC_RAM_MB     := 256
SOC_UBOOT_NOR  := isvp_a1n_sfcnor
endif

ifeq ($(SOC_MODEL),a1nt)
SOC_RAM_MB     := 256
SOC_UBOOT_NOR  := isvp_a1n_sfcnor
endif

ifeq ($(SOC_MODEL),a1x)
SOC_RAM_MB     := 256
SOC_UBOOT_NOR  := isvp_a1n_sfcnor
endif

ifeq ($(SOC_MODEL),a1l)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_a1n_sfcnor
endif

ifeq ($(SOC_MODEL),a1a)
SOC_RAM_MB     := 512
SOC_UBOOT_NOR  := isvp_a1n_sfcnor
endif

endif
