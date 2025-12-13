################################################################################
#
# thingino-libwebsockets
#
################################################################################

# Ensure libwebsockets pulls headers from the real zlib provider.
override LIBWEBSOCKETS_DEPENDENCIES := \
	$(filter-out zlib,$(LIBWEBSOCKETS_DEPENDENCIES)) \
	libzlib

# Virtual wrapper so we can rebuild this tweak if needed.
THINGINO_LIBWEBSOCKETS_DEPENDENCIES = libwebsockets

$(eval $(virtual-package))
