################################################################################
#
# sigmastar-lib
#
# Prebuilt SigmaStar MI userspace libraries. Nothing to compile -- the package
# is a fetch plus an install step.
#
# Companion to sigmastar-sdk, which holds the kernel side. The split follows
# thingino's Ingenic convention: ingenic-lib is prebuilt userspace, ingenic-sdk
# is kernel-side.
#
# The Raptor HAL *dlopens* these rather than linking them, so nothing here is a
# link-time dependency -- but an image without them has daemons that start and
# then fail at the first HAL call.
#
################################################################################

SIGMASTAR_LIB_SITE_METHOD = git
SIGMASTAR_LIB_SITE = https://github.com/johnchia/sigmastar-lib
SIGMASTAR_LIB_SITE_BRANCH = main
SIGMASTAR_LIB_VERSION = 6742ba660ee40ad85ddae28e916b2b93a88e9c49
SIGMASTAR_LIB_LICENSE = PROPRIETARY
SIGMASTAR_LIB_REDISTRIBUTE = NO

# Alkaid release, read from the build stamp the libraries carry rather than
# inferred:
#
#   strings libmi_sys.so | grep 'Sigmastar Module'
#
# The vendor names a drop by its build date, so 0607 is 2022-06-07. Both values
# below describe the *vendor's* build, not ours -- the libraries were compiled
# with GCC 9.1.0 against glibc long before this tree's toolchain existed, and
# the path has to name what is in the repo.
SIGMASTAR_LIB_SDK_VERSION = 0607
SIGMASTAR_LIB_LIBC_NAME = glibc
SIGMASTAR_LIB_LIBC_VERSION = 9.1.0

# Same shape as ingenic-lib.mk resolves: family, content type, then release,
# C library and toolchain version. A second family, release or libc is a
# directory in the repo rather than a change here.
#
# Not SIGMASTAR_LIB_DIR: pkg-generic.mk defines <PKG>_DIR as the package build
# directory, so that name is silently overwritten and the path collapses to
# $(@D). ingenic-lib.mk calls its equivalent SDK_LIB_DIR for the same reason.
SIGMASTAR_LIB_BLOBS = $(@D)/$(SOC_FAMILY_CAPS)/lib/$(SIGMASTAR_LIB_SDK_VERSION)/$(SIGMASTAR_LIB_LIBC_NAME)/$(SIGMASTAR_LIB_LIBC_VERSION)

define SIGMASTAR_LIB_INSTALL_TARGET_CMDS
	$(INSTALL) -m 755 -d $(TARGET_DIR)/usr/lib
	$(INSTALL) -m 644 -t $(TARGET_DIR)/usr/lib $(SIGMASTAR_LIB_BLOBS)/*.so
endef

$(eval $(generic-package))
