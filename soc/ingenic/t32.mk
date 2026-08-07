# Ingenic T32 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t32lq t32nq t32vn),)

SOC_FAMILY    := t32
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t32lq)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t32lq_sfcnor
endif

ifeq ($(SOC_MODEL),t32nq)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t32nq_sfcnor
endif

ifeq ($(SOC_MODEL),t32vn)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t32vn_sfcnor
endif

endif
