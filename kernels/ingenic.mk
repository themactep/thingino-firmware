# Which kernels Ingenic SoCs run.
#
# Not a SoC property, which is why this is not in soc/: a family runs two or
# three kernels, and which branch it takes is mostly decided by the
# architecture rather than the family.
#
# One chain per version: the families that differ, then the branch the rest of
# the architecture shares. Leaving KERNEL_BRANCH unset rejects the combination;
# thingino.mk turns that into an error rather than a fallback.

KERNEL_SITE := https://github.com/gtxaspec/thingino-linux

# What a board gets when its defconfig names no version.
ifeq ($(KERNEL_VERSION),)
ifeq ($(SOC_ARCH),xburst2)
KERNEL_VERSION := 4.4.94
else
KERNEL_VERSION := 3.10.14
endif
endif

ifeq ($(KERNEL_VERSION),3.10.14)

ifeq ($(SOC_FAMILY),t32)
KERNEL_BRANCH := ingenic-t32
else ifeq ($(SOC_FAMILY),t41)
KERNEL_BRANCH := ingenic-t41-3.10.14
# ingenic-t31 covers all of xburst1; it is not a t31 branch. The architecture is
# tested rather than closing with a bare else so that an xburst2 family arriving
# without a 3.10 branch is rejected instead of taking this one.
else ifeq ($(SOC_ARCH),xburst1)
KERNEL_BRANCH := ingenic-t31
endif

else ifeq ($(KERNEL_VERSION),4.4.94)

ifeq ($(SOC_FAMILY),a1)
KERNEL_BRANCH := ingenic-a1
else ifeq ($(SOC_FAMILY),t23)
KERNEL_BRANCH := ingenic-t23-4.4.94
KERNEL_HASH   := b8a1f1ed22272b844fd423871f4aca16e8b779ff
else ifeq ($(SOC_FAMILY),t32)
KERNEL_BRANCH := ingenic-t32-4.4.94
else ifeq ($(SOC_FAMILY),t40)
KERNEL_BRANCH := ingenic-t40
else ifeq ($(SOC_FAMILY),t41)
KERNEL_BRANCH := ingenic-t41-4.4.94
# xburst2 shares no 4.4 branch: every family above names its own.
else ifeq ($(SOC_ARCH),xburst1)
KERNEL_BRANCH := ingenic-t31-4.4.94
endif

else ifeq ($(KERNEL_VERSION),7.1-rc1)

# One branch for every family, whatever the architecture.
KERNEL_BRANCH := ingenic-7.1-rc1

endif
