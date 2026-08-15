# Ingenic C100. Included for every board; the filter
# below is what limits it to this family's models.
#
# A t31 part, but a family of its own: it runs 4.4 only, which is the condition
# the old lookup tested for. With no second case left there is nothing to test.
ifneq ($(filter $(SOC_MODEL),c100),)

SOC_FAMILY    := c100
SOC_ARCH      := xburst1
SOC_UBOOT_BIN := u-boot-with-tpl-lzma.bin
SOC_RAM_MB    := 128
SOC_UBOOT     := $(if $(BR2_THINGINO_FLASH_NAND),isvp_t31a_sfcnand,isvp_t31a_sfcnor)

endif
