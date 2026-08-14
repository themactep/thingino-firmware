# Ingenic T32 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t32lq t32nq t32vn),)

# what's common
SOC_FAMILY    := t32
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

# what's different
ifeq ($(SOC_MODEL),t32lq)
SOC_RAM_MB    := 64
SOC_UBOOT     := isvp_t32lq_sfcnor
else ifeq ($(SOC_MODEL),t32nq)
SOC_RAM_MB    := 128
SOC_UBOOT     := isvp_t32nq_sfcnor
else
SOC_RAM_MB    := 128
SOC_UBOOT     := isvp_t32vn_sfcnor
endif

endif
