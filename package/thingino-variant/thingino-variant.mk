################################################################################
#
# thingino-variant
#
################################################################################

# Virtual package - no source. Exists only to carry the firmware variant
# choice and the per-tier package selects.
THINGINO_VARIANT_LICENSE = N/A

$(eval $(virtual-package))
