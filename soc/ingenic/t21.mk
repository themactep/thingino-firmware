# Ingenic T21 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t21l t21n t21x t21zn t21zl),)

# what's common
SOC_ARCH      := xburst1
SOC_FAMILY    := t21
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin
SOC_UBOOT     := isvp_t21n_sfcnor

# what's different
ifeq ($(SOC_MODEL),t21x)
SOC_RAM_MB    := 128
else
SOC_RAM_MB    := 64
endif

endif
