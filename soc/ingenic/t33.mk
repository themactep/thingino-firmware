# Ingenic T33 family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),t33dl t33l t33lq t33n t33vl t33vn t33zl t33zn),)

# what's common
SOC_ARCH   := xburst1
SOC_FAMILY := t33
SOC_UBOOT  := isvp_t33_sfcnor

# what's different
ifneq ($(filter $(SOC_MODEL),t33n t33vn t33zn),)
SOC_RAM_MB := 128
else
SOC_RAM_MB := 64
endif

endif
