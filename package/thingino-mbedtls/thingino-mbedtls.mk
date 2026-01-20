################################################################################
#
# thingino-mbedtls - virtual package that selects the custom mbedtls build
#
################################################################################

# The actual mbedtls overrides live in mbedtls-override.mk.
THINGINO_MBEDTLS_DEPENDENCIES = mbedtls

$(eval $(virtual-package))