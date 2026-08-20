################################################################################
#
# buildscope - Buildroot output size and composition analyzer (host tool)
#
################################################################################

BUILDSCOPE_LICENSE = MIT

ifeq ($(BR2_PACKAGE_HOST_BUILDSCOPE_PREBUILT),y)

# A release tag rather than a commit: the binaries hang off the tag. Keep this
# in step with BUILDSCOPE_VERSION in .github/workflows/firmware-master.yaml,
# which puts the same binary on PATH so CI gets a report from a container that
# never configured the package.
BUILDSCOPE_VERSION = 0.1.9

# Static musl, built natively per architecture, so what has to match is the
# machine this build runs on: HOSTARCH, the userland the host compiler targets,
# and not the camera we are building for.
BUILDSCOPE_SOURCE = buildscope-$(HOSTARCH)-unknown-linux-musl
BUILDSCOPE_SITE = https://github.com/thingino/buildscope/releases/download/v$(BUILDSCOPE_VERSION)

# The asset name carries no version, so a version bump lands on the name
# already in the download cache. That is safe rather than stale: the cached
# file fails the hash below and dl-wrapper re-downloads it. It does mean the
# hash has to move with BUILDSCOPE_VERSION or every build stops here.
#
# It is a bare ELF and not an archive, so there is nothing to unpack, and the
# default extract step would refuse the unknown suffix.
define HOST_BUILDSCOPE_EXTRACT_CMDS
	cp $(HOST_BUILDSCOPE_DL_DIR)/$(BUILDSCOPE_SOURCE) $(@D)/buildscope
endef

# wget leaves the download unreadable as a program; install it executable.
define HOST_BUILDSCOPE_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/buildscope $(HOST_DIR)/bin/buildscope
endef

$(eval $(host-generic-package))

else

BUILDSCOPE_VERSION = 4d65bdffe40fa6e1b8c1deeefa5ba8832749469a
BUILDSCOPE_SITE = $(call github,thingino,buildscope,$(BUILDSCOPE_VERSION))
BUILDSCOPE_LICENSE_FILES = LICENSE

# Buildroot vendors the cargo dependencies into the tarball it downloads and
# names it after the post-process format it used, so the archive is neither
# reproducible nor stably named. buildscope.hash covers the release binaries;
# exempt this one rather than chase it on every bump.
BR_NO_CHECK_HASH_FOR += $(HOST_BUILDSCOPE_SOURCE)

# The repository is a cargo workspace whose root is a virtual manifest, so the
# CLI crate is built from its own subdirectory; the vendored dependencies and
# the lockfile at the archive root are still picked up from there.
HOST_BUILDSCOPE_SUBDIR = cli

$(eval $(host-cargo-package))

endif
