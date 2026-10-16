################################################################################
#
# thingino-motor - vendor T31 TCU stepper motor driver (/dev/motor)
#
################################################################################

THINGINO_MOTOR_VERSION = 1.0
THINGINO_MOTOR_SITE = $(THINGINO_MOTOR_PKGDIR)/src
THINGINO_MOTOR_SITE_METHOD = local
# Ingenic SDK driver, redistributed under the SDK licence.
THINGINO_MOTOR_LICENSE = Ingenic SDK
THINGINO_MOTOR_DEPENDENCIES = linux

# The in-tree driver is the 2025 "PP/TCU" motor driver from
# overrides/ingenic-sdk/common/misc/motors-pp (the improved implementation
# that takes the per-camera parameters S59motor passes: tcu_channels,
# hmaxstep/vmaxstep, and the hst1..4/vst1..4 phase pins), plus its tcu_alloc
# helper. Both build in this one dir so motor's tcu_alloc_* symbols resolve.
#
# Ported to the 5.15 vendor tree: the code selects the ingenic_tcu_chn path
# for CONFIG_SOC_T40 || CONFIG_KERNEL_4_4_94, so -DCONFIG_KERNEL_5 makes the
# 5.15 T31 tree take that path too (the 5.15 ingenic-tcu MFD creates the
# "ingenic,tcu_chn2" cell from the DT child compatible); and the /proc fops
# were updated to struct proc_ops.
THINGINO_MOTOR_MODULE_SUBDIRS = .
THINGINO_MOTOR_MODULE_MAKE_OPTS = \
	KDIR=$(LINUX_DIR) \
	INSTALL_MOD_PATH=$(TARGET_DIR) \
	INSTALL_MOD_DIR=ingenic \
	DIR=. \
	EXTRA_CFLAGS="-DCONFIG_KERNEL_5=1 \
	-I$(LINUX_DIR)/arch/mips/xburst/soc-t31/include \
	-I$(LINUX_DIR)/arch/mips/xburst/core/include \
	-I$(LINUX_DIR)/arch/mips/xburst/common/include"

$(eval $(kernel-module))
$(eval $(generic-package))
