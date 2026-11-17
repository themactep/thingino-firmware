# Novatek NA51055 family (NT98528/NT98529, sold for dashcams as NT96580/NT9657x).
# Included for every board; the filter limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),nt98528 nt98529),)

SOC_ARCH   := cortex-a9
SOC_FAMILY := na51055
SOC_RAM_MB := 512

endif
