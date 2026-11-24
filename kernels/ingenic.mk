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
ifneq ($(filter xburst2,$(SOC_ARCH))$(filter t33,$(SOC_FAMILY)),)
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
# The T33 has no 3.10 branch; leaving it unset rejects the combination
# instead of letting the xburst1 line below give it the T31's kernel.
else ifeq ($(SOC_FAMILY),t33)
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
KERNEL_HASH   := f97f65461547f1543ee3da22e72612f29a797cb3
else ifeq ($(SOC_FAMILY),t32)
KERNEL_BRANCH := ingenic-t32-4.4.94
else ifeq ($(SOC_FAMILY),t33)
KERNEL_BRANCH := ingenic-t33-4.4.94
else ifeq ($(SOC_FAMILY),t40)
KERNEL_BRANCH := ingenic-t40
else ifeq ($(SOC_FAMILY),t41)
KERNEL_BRANCH := ingenic-t41-4.4.94
# xburst2 shares no 4.4 branch: every family above names its own.
else ifeq ($(SOC_ARCH),xburst1)
KERNEL_BRANCH := ingenic-t31-4.4.94
endif

else ifeq ($(KERNEL_VERSION),7.4)

# Mainline lives in gtxaspec/linux: one branch for every supported family.
KERNEL_SITE := https://github.com/gtxaspec/linux

ifneq ($(filter t10 t20 t21 t23 t30 t31,$(SOC_FAMILY)),)
KERNEL_BRANCH := ingenic-7.4
KERNEL_HASH   := 8dd20b87c85dc2c24643365de337f4eba907a7a3
endif

endif
