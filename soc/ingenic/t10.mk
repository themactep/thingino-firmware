# Ingenic T10 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t10l t10n t10a),)

# what's common
SOC_ARCH      := xburst1
SOC_FAMILY    := t10
SOC_RAM_MB    := 64
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

# what's different
ifeq ($(SOC_MODEL),t10l)
SOC_UBOOT     := isvp_t10l_sfcnor
else
SOC_UBOOT     := isvp_t10n_sfcnor
endif

endif
