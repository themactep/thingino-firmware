################################################################################
#
# buildscope - Buildroot output size and composition analyzer (host tool)
#
################################################################################

BUILDSCOPE_VERSION = c7e0ccedfcdf0e501b6e8c397de8825a7926f415
BUILDSCOPE_SITE = $(call github,thingino,buildscope,$(BUILDSCOPE_VERSION))

BUILDSCOPE_LICENSE = MIT
BUILDSCOPE_LICENSE_FILES = LICENSE

# The repository is a cargo workspace whose root is a virtual manifest, so the
# CLI crate is built from its own subdirectory; the vendored dependencies and
# the lockfile at the archive root are still picked up from there.
HOST_BUILDSCOPE_SUBDIR = cli

$(eval $(host-cargo-package))
