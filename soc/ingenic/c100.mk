ifeq ($(KERNEL_VERSION),4.4.94)
SOC_FAMILY     := c100
else
SOC_FAMILY     := t31
endif
SOC_ARCH       := xburst1
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31a_sfcnor
SOC_UBOOT_NAND := isvp_t31a_sfcnand
SOC_UBOOT_BIN  := u-boot-with-tpl-lzma.bin
