################################################################################
#
# rtl8188fu-openipc
#
################################################################################

RTL8188FU_OPENIPC_VERSION = a4dae1f8a417fce807e59936507c4abc1379792d
RTL8188FU_OPENIPC_SITE = $(call github,themactep,ingenic-rtl8188ftv,$(RTL8188FU_OPENIPC_VERSION))
RTL8188FU_OPENIPC_LICENSE = GPL-2.0

RTL8188FU_OPENIPC_MODULE_MAKE_OPTS = \
	CONFIG_RTL8188FU=m \
	KVER=$(LINUX_VERSION_PROBED) \
	KSRC=$(LINUX_DIR)

$(eval $(kernel-module))
$(eval $(generic-package))
