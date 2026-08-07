################################################################################
#
# buildscope - Buildroot output size and composition analyzer (host tool)
#
################################################################################

BUILDSCOPE_VERSION = afa9252925afdbe0ecb88bb9f62145390dfafa16
BUILDSCOPE_SITE = $(call github,thingino,buildscope,$(BUILDSCOPE_VERSION))

BUILDSCOPE_LICENSE = MIT
BUILDSCOPE_LICENSE_FILES = LICENSE

# The repository is a cargo workspace whose root is a virtual manifest, so the
# CLI crate is built from its own subdirectory; the vendored dependencies and
# the lockfile at the archive root are still picked up from there.
HOST_BUILDSCOPE_SUBDIR = cli

$(eval $(host-cargo-package))
