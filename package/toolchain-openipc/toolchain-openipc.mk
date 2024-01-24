################################################################################
#
# external toolchain for building openipc
#
################################################################################

ifeq ($(BR2_PACKAGE_TOOLCHAIN_OPENIPC),y)
BR2_TOOLCHAIN_EXTERNAL_URL="https://github.com/openipc/firmware/releases/download/$(OPENIPC_TOOLCHAIN).tgz"

ifeq ($(BR2_arm),y)
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="arm-openipc-linux-musleabi"

else ifeq ($(BR2_mipsel),y)
ifeq ($(BR2_DEFAULT_KERNEL_VERSION),"3.10.14")
BR2_TOOLCHAIN_EXTERNAL_HEADERS_3_10=y
endif

BR2_TOOLCHAIN_EXTERNAL_CUSTOM_MUSL=y
BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="mipsel-openipc-linux-musl"
endif
endif

$(eval $(generic-package))
