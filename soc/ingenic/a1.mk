# Ingenic A1 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),a1n a1nt a1x a1l a1a),)

# what's common
SOC_ARCH   := xburst2
SOC_FAMILY := a1
SOC_UBOOT  := isvp_a1n_sfcnor

# what's different
ifeq ($(SOC_MODEL),a1l)
SOC_RAM_MB := 128
else ifeq ($(SOC_MODEL),a1a)
SOC_RAM_MB := 512
else
SOC_RAM_MB := 256
endif

endif
