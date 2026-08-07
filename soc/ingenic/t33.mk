# Ingenic T33 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t33dl t33l t33lq t33n t33vl t33vn t33zl t33zn),)

SOC_FAMILY    := t33
SOC_ARCH      := xburst1

ifeq ($(SOC_MODEL),t33dl)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33l)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33lq)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33n)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33vl)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33vn)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33zl)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

ifeq ($(SOC_MODEL),t33zn)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t33_sfcnor
endif

endif
