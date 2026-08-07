# Ingenic C100. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),c100),)

SOC_FAMILY    := t31
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

# A t31 part on 3.10.14, its own family on 4.4.94. Stated as data because
# KERNEL_VERSION is resolved after this file is read.
SOC_FAMILY_IF_KERNEL_4.4.94 := c100

SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31a_sfcnor
SOC_UBOOT_NAND := isvp_t31a_sfcnand

endif
