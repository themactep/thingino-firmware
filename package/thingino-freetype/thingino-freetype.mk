################################################################################
#
# thingino-freetype - shadow freetype with a newer version
#
################################################################################

# Bump Buildroot's freetype when this shadow package is enabled.
THINGINO_FREETYPE_DEPENDENCIES = freetype

$(eval $(virtual-package))
