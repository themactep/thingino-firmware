################################################################################
#
# sigmastar-uboot
#
# U-Boot for SigmaStar Infinity6-family SoCs, from OpenIPC's fork of the vendor
# tree. Builds a NOR boot image into images/ and installs nothing to the target.
#
# The artifact is not u-boot.bin. A SigmaStar NOR boot image is a container the
# mask ROM reads, assembled by make_boot_spinor.sh from four pieces at fixed
# offsets in the first 128KB -- IPL at 0, MXP_SF at 60k, IPL_CUST at 64k -- with
# the compressed U-Boot appended at 128k. The first three are vendor blobs
# carried in the tree; only the tail is built here. Flashing u-boot.bin instead
# produces a board that does not boot and cannot be recovered over the network.
#
# The SoC model reaches the compiler as a define rather than a defconfig: one
# defconfig covers the whole family and PRODUCT_SOC selects the DDR timing and
# pinmux within it. Both values come from the camera defconfig, so a second
# SigmaStar board needs no change here.
#
# Building this does not flash it, and nothing in the image references it. The
# boot partition is the only one on this board where a bad write cannot be
# undone in software.
#
################################################################################

SIGMASTAR_UBOOT_VERSION = bf77aff5d44f34d14b89b3f4014aa8dda9834794
SIGMASTAR_UBOOT_SITE = https://github.com/openipc/u-boot-sigmastar
SIGMASTAR_UBOOT_SITE_METHOD = git
SIGMASTAR_UBOOT_LICENSE = GPL-2.0+ (u-boot), PROPRIETARY (ipl/)
SIGMASTAR_UBOOT_LICENSE_FILES = Licenses/gpl-2.0.txt
SIGMASTAR_UBOOT_REDISTRIBUTE = NO
SIGMASTAR_UBOOT_INSTALL_IMAGES = YES
SIGMASTAR_UBOOT_INSTALL_TARGET = NO
SIGMASTAR_UBOOT_INSTALL_STAGING = NO

# From thingino.mk's exported environment, not from .config: the model reaches
# Kconfig too, but the family is derived there and never written back. Both are
# checked below because an empty one here builds a target named "_defconfig" and
# fails several steps later with nothing naming the cause.
SIGMASTAR_UBOOT_SOC_MODEL = $(SOC_MODEL)
SIGMASTAR_UBOOT_SOC_FAMILY = $(SOC_FAMILY)

ifeq ($(SIGMASTAR_UBOOT_SOC_MODEL),)
$(error sigmastar-uboot: SOC_MODEL is empty -- expected it exported by thingino.mk)
endif
ifeq ($(SIGMASTAR_UBOOT_SOC_FAMILY),)
$(error sigmastar-uboot: SOC_FAMILY is empty -- expected it exported by thingino.mk)
endif

# For mkenvimage, which the post-image script uses to build the environment
# image describing the partition table. host-uboot-tools installs it
# unconditionally. BR2_PACKAGE_HOST_UBOOT_TOOLS_ENVIMAGE is a different thing
# and not what is wanted here -- it asks Buildroot to generate an environment
# image from a static source file, which cannot express a table whose sizes
# come from the images this build produces.
SIGMASTAR_UBOOT_DEPENDENCIES = host-uboot-tools

SIGMASTAR_UBOOT_MAKE_ENV = ARCH=arm CROSS_COMPILE="$(TARGET_CROSS)"

define SIGMASTAR_UBOOT_CONFIGURE_CMDS
	$(SIGMASTAR_UBOOT_MAKE_ENV) $(MAKE1) -C $(@D) \
		$(SIGMASTAR_UBOOT_SOC_FAMILY)_defconfig
endef

define SIGMASTAR_UBOOT_BUILD_CMDS
	$(SIGMASTAR_UBOOT_MAKE_ENV) $(MAKE) -C $(@D) \
		KCFLAGS=-DPRODUCT_SOC=$(SIGMASTAR_UBOOT_SOC_MODEL)
	cd $(@D) && $(SHELL) make_boot_spinor.sh $(SIGMASTAR_UBOOT_SOC_FAMILY)
endef

define SIGMASTAR_UBOOT_INSTALL_IMAGES_CMDS
	$(INSTALL) -D -m 0644 $(@D)/BOOT.bin \
		$(BINARIES_DIR)/u-boot-$(SIGMASTAR_UBOOT_SOC_MODEL)-nor.bin
endef

$(eval $(generic-package))
