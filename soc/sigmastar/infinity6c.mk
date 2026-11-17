# SigmaStar Infinity6C family. Included for every board; the filter
# below is what limits it to this family's models.
ifneq ($(filter $(SOC_MODEL),ssc377 ssc377d ssc377de ssc377qe ssc378de ssc378qe),)

# what's common
SOC_FAMILY := infinity6c
SOC_ARCH   := infinity6c

# what's different
SOC_RAM_MB_ssc377   := 64
SOC_RAM_MB_ssc377d  := 128
SOC_RAM_MB_ssc377de := 128
SOC_RAM_MB_ssc377qe := 256
SOC_RAM_MB_ssc378de := 128
SOC_RAM_MB_ssc378qe := 256
SOC_RAM_MB := $(SOC_RAM_MB_$(SOC_MODEL))

endif
