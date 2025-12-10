################################################################################
#
# thingino-live555 - virtual package that selects the custom live555 build
#
################################################################################

# The actual live555 overrides live in live555-override.mk.
THINGINO_LIVE555_DEPENDENCIES = live555

$(eval $(virtual-package))
