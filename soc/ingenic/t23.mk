# Ingenic T23 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t23n t23dl t23zn),)

# what's common
SOC_FAMILY    := t23
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

# what's different
ifeq ($(SOC_MODEL),t23n)
SOC_RAM_MB    := 64
SOC_UBOOT     := isvp_t23n_sfcnor
else ifeq ($(SOC_MODEL),t23dl)
SOC_RAM_MB    := 32
SOC_UBOOT     := isvp_t23dl_sfcnor
else
SOC_RAM_MB    := 64
SOC_UBOOT     := isvp_t23zn_sfcnor
endif

endif
