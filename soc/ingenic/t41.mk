# Ingenic T41 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t41lq t41nq t41zl t41zn t41zx t41a),)

SOC_FAMILY    := t41
SOC_ARCH      := xburst2

ifeq ($(SOC_MODEL),t41lq)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t41lq_sfcnor
SOC_UBOOT_NAND := isvp_t41lq_sfc0_nand
endif

ifeq ($(SOC_MODEL),t41nq)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t41nq_sfcnor
SOC_UBOOT_NAND := isvp_t41nq_sfc0_nand
endif

ifeq ($(SOC_MODEL),t41zl)
SOC_RAM_MB     := 64
SOC_UBOOT_NOR  := isvp_t41lq_sfcnor
SOC_UBOOT_NAND := isvp_t41l_sfc0_nand
endif

ifeq ($(SOC_MODEL),t41zn)
SOC_RAM_MB     := 128
SOC_UBOOT_NOR  := isvp_t41nq_sfcnor
SOC_UBOOT_NAND := isvp_t41n_sfc0_nand
endif

ifeq ($(SOC_MODEL),t41zx)
SOC_RAM_MB     := 256
SOC_UBOOT_NOR  := isvp_t41nq_sfcnor
SOC_UBOOT_NAND := isvp_t41zx_sfc0_nand
endif

ifeq ($(SOC_MODEL),t41a)
SOC_RAM_MB     := 512
SOC_UBOOT_NOR  := isvp_t41nq_sfcnor
SOC_UBOOT_NAND := isvp_t41a_sfc0_nand
endif

endif
