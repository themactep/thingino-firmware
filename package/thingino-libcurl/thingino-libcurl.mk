################################################################################
#
# thingino-libcurl - virtual package that applies custom libcurl overrides
#
################################################################################

# The actual libcurl overrides live in libcurl-override.mk.
THINGINO_LIBCURL_DEPENDENCIES = libcurl

$(eval $(virtual-package))
