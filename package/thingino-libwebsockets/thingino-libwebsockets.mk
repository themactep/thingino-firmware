################################################################################
#
# thingino-libwebsockets - virtual package that selects the custom libwebsockets build
#
################################################################################

# The actual libwebsockets overrides live in libwebsockets-override.mk.
THINGINO_LIBWEBSOCKETS_DEPENDENCIES = libwebsockets

$(eval $(virtual-package))
