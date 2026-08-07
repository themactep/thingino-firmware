# Ingenic T31 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t31l t31lc t31n t31x t31a t31al t31zl t31zx c100),)

SOC_FAMILY    := t31
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin

ifeq ($(SOC_MODEL),t31l)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t31l_sfcnor
SOC_UBOOT_NAND := isvp_t31_sfcnand_lite
endif

ifeq ($(SOC_MODEL),t31lc)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t31lc_sfcnor
endif

ifeq ($(SOC_MODEL),t31n)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t31n_sfcnor
SOC_UBOOT_NAND := isvp_t31_sfcnand
endif

ifeq ($(SOC_MODEL),t31x)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31x_sfcnor
SOC_UBOOT_NAND := isvp_t31_sfcnand_ddr128M
endif

ifeq ($(SOC_MODEL),t31a)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31a_sfcnor
SOC_UBOOT_NAND := isvp_t31a_sfcnand_ddr128M
endif

ifeq ($(SOC_MODEL),t31al)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31x_sfcnor
SOC_UBOOT_NAND := isvp_t31al_sfcnand_ddr128M
endif

ifeq ($(SOC_MODEL),t31zl)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t31n_sfcnor
SOC_UBOOT_NAND := isvp_t31_sfcnand_lite
endif

ifeq ($(SOC_MODEL),t31zx)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31x_sfcnor
SOC_UBOOT_NAND := isvp_t31_sfcnand_ddr128M
endif

ifeq ($(SOC_MODEL),c100)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t31a_sfcnor
SOC_UBOOT_NAND := isvp_t31a_sfcnand
# The one model whose family is not fixed by the part.
ifeq ($(KERNEL_VERSION),4.4.94)
SOC_FAMILY := c100
endif
endif

endif
