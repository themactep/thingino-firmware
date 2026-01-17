################################################################################
#
# U-Boot for Ingenic MIPS on Thingino
#
################################################################################

THINGINO_UBOOT_VERSION = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_VERSION))
THINGINO_UBOOT_BOARD_NAME = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME))

THINGINO_UBOOT_LICENSE = GPL-2.0+
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_LATEST_VERSION),y)
THINGINO_UBOOT_LICENSE_FILES = Licenses/gpl-2.0.txt
endif
THINGINO_UBOOT_CPE_ID_VENDOR = denx
THINGINO_UBOOT_CPE_ID_PRODUCT = u-boot

THINGINO_UBOOT_INSTALL_IMAGES = YES

TARGET_LDFLAGS:=$(filter-out -ztext,$(TARGET_LDFLAGS))

# u-boot 2020.01+ needs make 4.0+
THINGINO_UBOOT_DEPENDENCIES = host-pkgconf $(BR2_MAKE_HOST_DEPENDENCY)
THINGINO_UBOOT_MAKE = $(BR2_MAKE)

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL),y)
# Handle custom U-Boot tarballs as specified by the configuration
THINGINO_UBOOT_TARBALL = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL_LOCATION))
THINGINO_UBOOT_SITE = $(patsubst %/,%,$(dir $(THINGINO_UBOOT_TARBALL)))
THINGINO_UBOOT_SOURCE = $(notdir $(THINGINO_UBOOT_TARBALL))
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_GIT),y)
THINGINO_UBOOT_SITE = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_URL))
THINGINO_UBOOT_SITE_METHOD = git
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_HG),y)
THINGINO_UBOOT_SITE = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_URL))
THINGINO_UBOOT_SITE_METHOD = hg
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_SVN),y)
THINGINO_UBOOT_SITE = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_URL))
THINGINO_UBOOT_SITE_METHOD = svn
else
# Handle stable official U-Boot versions
THINGINO_UBOOT_SITE = https://ftp.denx.de/pub/u-boot
THINGINO_UBOOT_SOURCE = u-boot-$(THINGINO_UBOOT_VERSION).tar.bz2
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT)$(BR2_PACKAGE_THINGINO_UBOOT_LATEST_VERSION),y)
BR_NO_CHECK_HASH_FOR += $(THINGINO_UBOOT_SOURCE)
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_BIN),y)
THINGINO_UBOOT_BINS += u-boot.bin
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_DTB),y)
THINGINO_UBOOT_BINS += u-boot.dtb
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_ELF),y)
THINGINO_UBOOT_BINS += u-boot
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_REMAKE_ELF),y)
THINGINO_UBOOT_BINS += u-boot.elf
endif

# Call 'make all' unconditionally
THINGINO_UBOOT_MAKE_TARGET += all

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_INITIAL_ENV),y)
THINGINO_UBOOT_MAKE_TARGET += u-boot-initial-env
define THINGINO_UBOOT_INSTALL_THINGINO_UBOOT_INITIAL_ENV
	$(INSTALL) -D -m 0644 $(@D)/u-boot-initial-env $(TARGET_DIR)/etc/u-boot-initial-env
endef
THINGINO_UBOOT_POST_INSTALL_TARGET_HOOKS += THINGINO_UBOOT_INSTALL_THINGINO_UBOOT_INITIAL_ENV
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM),y)
THINGINO_UBOOT_BINS += $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME))
endif

# Ingenic uses MIPS architecture
THINGINO_UBOOT_ARCH = $(NORMALIZED_ARCH)

THINGINO_UBOOT_MAKE_OPTS += \
	CROSS_COMPILE="$(TARGET_CROSS)" \
	ARCH=$(THINGINO_UBOOT_ARCH) \
	HOSTCC="$(HOSTCC) $(subst -I/,-isystem /,$(subst -I /,-isystem /,$(HOST_CFLAGS)))" \
	HOSTLDFLAGS="$(HOST_LDFLAGS)" \
	$(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_MAKEOPTS))

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_ENABLE_BAR),y)
THINGINO_UBOOT_MAKE_OPTS += CONFIG_SPI_FLASH_BAR=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_EXTERNAL_ENV_ENABLE),y)
THINGINO_UBOOT_MAKE_OPTS += CONFIG_BOOTARGS_EXTERNAL=1
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_PHY_RESET_AFTER_CONFIG),y)
THINGINO_UBOOT_MAKE_OPTS += CONFIG_PHY_RESET_AFTER_CONFIG=1
THINGINO_UBOOT_MAKE_OPTS += CONFIG_GPIO_PHY_RESET=$(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_GPIO_PHY_RESET))
THINGINO_UBOOT_MAKE_OPTS += CONFIG_GPIO_PHY_RESET_ENLEVEL=$(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_GPIO_PHY_RESET_ENLEVEL))
endif

# Disable FDPIC if enabled by default in toolchain
ifeq ($(BR2_BINFMT_FDPIC),y)
THINGINO_UBOOT_MAKE_OPTS += KCFLAGS=-mno-fdpic
endif

# Ingenic-specific build dependencies
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_NEEDS_LZOP),y)
THINGINO_UBOOT_DEPENDENCIES += host-lzop
endif

# prior to u-boot 2013.10 the license info was in COPYING. Copy it so
# legal-info finds it
define THINGINO_UBOOT_COPY_OLD_LICENSE_FILE
	if [ -f $(@D)/COPYING ]; then \
		$(INSTALL) -m 0644 -D $(@D)/COPYING $(@D)/Licenses/gpl-2.0.txt; \
	fi
endef

THINGINO_UBOOT_POST_EXTRACT_HOOKS += THINGINO_UBOOT_COPY_OLD_LICENSE_FILE
THINGINO_UBOOT_POST_RSYNC_HOOKS += THINGINO_UBOOT_COPY_OLD_LICENSE_FILE

# Older versions break on gcc 10+ because of redefined symbols
define THINGINO_UBOOT_DROP_YYLLOC
	$(Q)grep -Z -l -r -E '^YYLTYPE yylloc;$$' $(@D) \
	|xargs -0 -r $(SED) '/^YYLTYPE yylloc;$$/d'
endef
THINGINO_UBOOT_POST_PATCH_HOOKS += THINGINO_UBOOT_DROP_YYLLOC

# Copy sha1.h to tools directory for tools build
define THINGINO_UBOOT_COPY_SHA1_HEADER
	cp $(@D)/include/sha1.h $(@D)/tools/sha1.h
endef
THINGINO_UBOOT_POST_PATCH_HOOKS += THINGINO_UBOOT_COPY_SHA1_HEADER

# Analogous code exists in linux/linux.mk. Basically, the generic
# package infrastructure handles downloading and applying remote
# patches. Local patches are handled depending on whether they are
# directories or files.
THINGINO_UBOOT_PATCHES = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_PATCH))
THINGINO_UBOOT_PATCH = $(filter ftp://% http://% https://%,$(THINGINO_UBOOT_PATCHES))

define THINGINO_UBOOT_APPLY_LOCAL_PATCHES
	for p in $(filter-out ftp://% http://% https://%,$(THINGINO_UBOOT_PATCHES)) ; do \
		if test -d $$p ; then \
			$(APPLY_PATCHES) $(@D) $$p \*.patch || exit 1 ; \
		else \
			$(APPLY_PATCHES) $(@D) `dirname $$p` `basename $$p` || exit 1; \
		fi \
	done
endef
THINGINO_UBOOT_POST_PATCH_HOOKS += THINGINO_UBOOT_APPLY_LOCAL_PATCHES

# Fixup inclusion of libfdt headers, which can fail in older u-boot versions
# when libfdt-devel is installed system-wide.
# The core change is equivalent to upstream commit
# e0d20dc1521e74b82dbd69be53a048847798a90a (first in v2018.03). However, the fixup
# is complicated by the fact that the underlying u-boot code changed multiple
# times in history:
# - The directory scripts/dtc/libfdt only exists since upstream commit
#   c0e032e0090d6541549b19cc47e06ccd1f302893 (first in v2017.11). For earlier
#   versions, create a dummy scripts/dtc/libfdt directory with symlinks for the
#   fdt-related files. This allows to use the same -I<path> option for both
#   cases.
# - The variable 'srctree' used to be called 'SRCTREE' before upstream commit
#   01286329b27b27eaeda045b469d41b1d9fce545a (first in v2014.04).
# - The original location for libfdt, 'lib/libfdt/', used to be simply
#   'libfdt' before upstream commit 0de71d507157c4bd4fddcd3a419140d2b986eed2
#   (first in v2010.06). Make the 'lib' part optional in the substitution to
#   handle this.
define THINGINO_UBOOT_FIXUP_LIBFDT_INCLUDE
	$(Q)if [ ! -d $(@D)/scripts/dtc/libfdt ]; then \
		mkdir -p $(@D)/scripts/dtc/libfdt; \
		cd $(@D)/scripts/dtc/libfdt; \
		ln -s ../../../include/fdt.h .; \
		ln -s ../../../include/libfdt*.h .; \
		ln -s ../../../lib/libfdt/libfdt_internal.h .; \
	fi
	$(Q)$(SED) \
		's%-I\ *\$$(srctree)/lib/libfdt%-I$$(srctree)/scripts/dtc/libfdt%; \
		s%-I\ *\$$(SRCTREE)\(/lib\)\?/libfdt%-I$$(SRCTREE)/scripts/dtc/libfdt%' \
		$(@D)/tools/Makefile
endef
THINGINO_UBOOT_POST_PATCH_HOOKS += THINGINO_UBOOT_FIXUP_LIBFDT_INCLUDE

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_LEGACY),y)
define THINGINO_UBOOT_CONFIGURE_CMDS
	$(TARGET_CONFIGURE_OPTS) \
		$(THINGINO_UBOOT_MAKE) -C $(@D) $(THINGINO_UBOOT_MAKE_OPTS) \
		$(THINGINO_UBOOT_BOARD_NAME)_config
endef
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_KCONFIG),y)
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_USE_DEFCONFIG),y)
THINGINO_UBOOT_KCONFIG_DEFCONFIG = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_BOARD_DEFCONFIG))_defconfig
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_USE_CUSTOM_CONFIG),y)
THINGINO_UBOOT_KCONFIG_FILE = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_CONFIG_FILE))
endif # BR2_PACKAGE_THINGINO_UBOOT_USE_DEFCONFIG

THINGINO_UBOOT_KCONFIG_FRAGMENT_FILES = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CONFIG_FRAGMENT_FILES))
THINGINO_UBOOT_KCONFIG_EDITORS = menuconfig xconfig gconfig nconfig

# THINGINO_UBOOT_MAKE_OPTS overrides HOSTCC / HOSTLDFLAGS to allow the build to
# find our host-openssl. However, this triggers a bug in the kconfig
# build script that causes it to build with /usr/include/ncurses.h
# (which is typically wchar) but link with
# $(HOST_DIR)/lib/libncurses.so (which is not).  We don't actually
# need any host-package for kconfig, so remove the HOSTCC/HOSTLDFLAGS
# override again. In addition, host-ccache is not ready at kconfig
# time, so use HOSTCC_NOCCACHE.
THINGINO_UBOOT_KCONFIG_OPTS = $(THINGINO_UBOOT_MAKE_OPTS) HOSTCC="$(HOSTCC_NOCCACHE)" HOSTLDFLAGS=""

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_DEFAULT_ENV_FILE_ENABLED),y)
UBOOT_DEFAULT_ENV_FILE = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_DEFAULT_ENV_FILE))
define THINGINO_UBOOT_KCONFIG_DEFAULT_ENV_FILE
	$(call KCONFIG_SET_OPT,CONFIG_USE_DEFAULT_ENV_FILE,y)
	$(call KCONFIG_SET_OPT,CONFIG_DEFAULT_ENV_FILE,"$(shell readlink -f $(THINGINO_UBOOT_DEFAULT_ENV_FILE))")
endef
endif
endif # BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_LEGACY

THINGINO_UBOOT_CUSTOM_DTS_PATH = $(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_DTS_PATH))

define THINGINO_UBOOT_BUILD_CMDS
	$(if $(THINGINO_UBOOT_CUSTOM_DTS_PATH),
		cp -f $(THINGINO_UBOOT_CUSTOM_DTS_PATH) $(@D)/arch/$(THINGINO_UBOOT_ARCH)/dts/
	)
	$(TARGET_CONFIGURE_OPTS) \
		PKG_CONFIG="$(PKG_CONFIG_HOST_BINARY)" \
		PKG_CONFIG_SYSROOT_DIR="/" \
		PKG_CONFIG_ALLOW_SYSTEM_CFLAGS=1 \
		PKG_CONFIG_ALLOW_SYSTEM_LIBS=1 \
		PKG_CONFIG_LIBDIR="$(HOST_DIR)/lib/pkgconfig:$(HOST_DIR)/share/pkgconfig" \
		$(THINGINO_UBOOT_MAKE) -C $(@D) $(THINGINO_UBOOT_MAKE_OPTS) \
		$(THINGINO_UBOOT_MAKE_TARGET)
	$(if $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_SD),
		$(@D)/tools/mxsboot sd $(@D)/u-boot.sb $(@D)/u-boot.sd)
	$(if $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_NAND),
		$(@D)/tools/mxsboot \
			-w $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_NAND_PAGE_SIZE) \
			-o $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_NAND_OOB_SIZE) \
			-e $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_NAND_ERASE_SIZE) \
			nand $(@D)/u-boot.sb $(@D)/u-boot.nand)
endef

define THINGINO_UBOOT_INSTALL_IMAGES_CMDS
	$(foreach f,$(THINGINO_UBOOT_BINS), \
			cp -dpf $(@D)/$(f) $(BINARIES_DIR)/
	)
	$(if $(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_NAND),
		cp -dpf $(@D)/u-boot.sb $(BINARIES_DIR))
	$(if $(BR2_PACKAGE_THINGINO_UBOOT_SPL),
		$(foreach f,$(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_SPL_NAME)), \
			cp -dpf $(@D)/$(f) $(BINARIES_DIR)/
		)
	)
endef

define THINGINO_UBOOT_KCONFIG_FIXUP_CMDS
	$(THINGINO_UBOOT_KCONFIG_DEFAULT_ENV_FILE)
endef

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT)$(BR_BUILDING),yy)

#
# Set internal variables for flash controller
#
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_JZ_SFC),y)
	UBOOT_FLASH_CONTROLLER := "jz_sfc"
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC_NAND),y)
	UBOOT_FLASH_CONTROLLER := "sfc_nand"
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC0_NOR),y)
	UBOOT_FLASH_CONTROLLER := "sfc0_nor"
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC1_NOR),y)
	UBOOT_FLASH_CONTROLLER := "sfc1_nor"
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC0_NAND),y)
	UBOOT_FLASH_CONTROLLER := "sfc0_nand"
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC1_NAND),y)
	UBOOT_FLASH_CONTROLLER := "sfc1_nand"
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_CUSTOM),y)
	UBOOT_FLASH_CONTROLLER := $(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_CUSTOM_STRING)
endif

#
# Calculate reserved memory values and export to uenv.txt
#
define RMEM_SET_VALUE
	if [ -n "$(ISP_RMEM_MB)" ]; then \
		if [ "$(SOC_FAMILY)" = "t20" -o "$(SOC_FAMILY)" = "t10" ]; then \
			osmem=$$(( $(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_ISPMEM_MB) )) && \
			ispmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_ISPMEM_MB)) * 0x100000 )) && \
			rmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB)) * 0x100000 )) && \
			grep -q "^osmem=$${osmem}M@0x0" $(OUTPUT_DIR)/uenv.txt || echo "osmem=$${osmem}M@0x0" >> $(OUTPUT_DIR)/uenv.txt && \
			grep -q "^ispmem=$(ISP_ISPMEM_MB)M@$$(printf '0x%x' $$ispmem_offset)" $(OUTPUT_DIR)/uenv.txt || echo "ispmem=$(ISP_ISPMEM_MB)M@$$(printf '0x%x' $$ispmem_offset)" >> $(OUTPUT_DIR)/uenv.txt && \
			grep -q "^rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" $(OUTPUT_DIR)/uenv.txt || echo "rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" >> $(OUTPUT_DIR)/uenv.txt; \
		elif [ "$(SOC_FAMILY)" = "t40" -o "$(SOC_FAMILY)" = "t41" ]; then \
			osmem=$$(( $(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_NMEM_MB) )) && \
			rmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB) - $(ISP_NMEM_MB)) * 0x100000 )) && \
			nmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_NMEM_MB)) * 0x100000 )) && \
			grep -q "^osmem=$${osmem}M@0x0" $(OUTPUT_DIR)/uenv.txt || echo "osmem=$${osmem}M@0x0" >> $(OUTPUT_DIR)/uenv.txt && \
			grep -q "^rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" $(OUTPUT_DIR)/uenv.txt || echo "rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" >> $(OUTPUT_DIR)/uenv.txt && \
			grep -q "^nmem=$(ISP_NMEM_MB)M@$$(printf '0x%x' $$nmem_offset)" $(OUTPUT_DIR)/uenv.txt || echo "nmem=$(ISP_NMEM_MB)M@$$(printf '0x%x' $$nmem_offset)" >> $(OUTPUT_DIR)/uenv.txt; \
			echo HELLO $(ISP_NMEM_MB); \
		else \
			osmem=$$(( $(SOC_RAM_MB) - $(ISP_RMEM_MB) )) && \
			rmem_offset=$$(( ($(SOC_RAM_MB) - $(ISP_RMEM_MB)) * 0x100000 )) && \
			grep -q "^osmem=$${osmem}M@0x0" $(OUTPUT_DIR)/uenv.txt || echo "osmem=$${osmem}M@0x0" >> $(OUTPUT_DIR)/uenv.txt && \
			grep -q "^rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" $(OUTPUT_DIR)/uenv.txt || echo "rmem=$(ISP_RMEM_MB)M@$$(printf '0x%x' $$rmem_offset)" >> $(OUTPUT_DIR)/uenv.txt; \
		fi; \
	else \
		echo "No ISP_RMEM_MB value set"; \
	fi
endef

THINGINO_UBOOT_PRE_BUILD_HOOKS += RMEM_SET_VALUE

#
# Replace appropriate values in uenv.txt with those from the device config
#

define THINGINO_GENERATE_UBOOT_ENV
	@env BR2_PACKAGE_THINGINO_UBOOT_ROOT='$(value BR2_PACKAGE_THINGINO_UBOOT_ROOT)' sh -c 'grep -q "^root=" $(OUTPUT_DIR)/uenv.txt || echo "root=$$BR2_PACKAGE_THINGINO_UBOOT_ROOT" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE='$(value BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE)' sh -c 'grep -q "^rootfstype=" $(OUTPUT_DIR)/uenv.txt || echo "rootfstype=$$BR2_PACKAGE_THINGINO_UBOOT_ROOTFSTYPE" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_INIT='$(value BR2_PACKAGE_THINGINO_UBOOT_INIT)' sh -c 'grep -q "^init=" $(OUTPUT_DIR)/uenv.txt || echo "init=$$BR2_PACKAGE_THINGINO_UBOOT_INIT" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_MTDPARTS='$(value BR2_PACKAGE_THINGINO_UBOOT_MTDPARTS)' sh -c 'grep -q "^mtdparts=" $(OUTPUT_DIR)/uenv.txt || echo "mtdparts=$$BR2_PACKAGE_THINGINO_UBOOT_MTDPARTS" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_BOOTARGS='$(value BR2_PACKAGE_THINGINO_UBOOT_BOOTARGS)' sh -c 'grep -q "^bootargs=" $(OUTPUT_DIR)/uenv.txt || echo "bootargs=$$BR2_PACKAGE_THINGINO_UBOOT_BOOTARGS" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_BOOTCMD='$(value BR2_PACKAGE_THINGINO_UBOOT_BOOTCMD)' sh -c 'grep -q "^bootcmd=" $(OUTPUT_DIR)/uenv.txt || echo "bootcmd=$$BR2_PACKAGE_THINGINO_UBOOT_BOOTCMD" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_BOOTCMD='$(value BR2_PACKAGE_THINGINO_UBOOT_BOOTCMD)' sh -c 'grep -q "^bootcmd=" $(OUTPUT_DIR)/uenv.txt || echo "bootcmd=$$BR2_PACKAGE_THINGINO_UBOOT_BOOTCMD" | sed "s/=\"/=/;s/\"$$//" >> $(OUTPUT_DIR)/uenv.txt'
	@env BR2_PACKAGE_THINGINO_UBOOT_SD_ENABLE='$(BR2_PACKAGE_THINGINO_UBOOT_SD_ENABLE)' sh -c 'if [ "$$BR2_PACKAGE_THINGINO_UBOOT_SD_ENABLE" = "y" ]; then grep -q "^disable_sd=" $(OUTPUT_DIR)/uenv.txt && sed -i "s/^disable_sd=.*/disable_sd=false/" $(OUTPUT_DIR)/uenv.txt || echo "disable_sd=false" >> $(OUTPUT_DIR)/uenv.txt; else grep -q "^disable_sd=" $(OUTPUT_DIR)/uenv.txt && sed -i "s/^disable_sd=.*/disable_sd=true/" $(OUTPUT_DIR)/uenv.txt || echo "disable_sd=true" >> $(OUTPUT_DIR)/uenv.txt; fi'
	@env BR2_PACKAGE_THINGINO_UBOOT_ETH_ENABLE='$(BR2_PACKAGE_THINGINO_UBOOT_ETH_ENABLE)' sh -c 'if [ "$$BR2_PACKAGE_THINGINO_UBOOT_ETH_ENABLE" = "y" ]; then grep -q "^disable_eth=" $(OUTPUT_DIR)/uenv.txt && sed -i "s/^disable_eth=.*/disable_eth=false/" $(OUTPUT_DIR)/uenv.txt || echo "disable_eth=false" >> $(OUTPUT_DIR)/uenv.txt; else grep -q "^disable_eth=" $(OUTPUT_DIR)/uenv.txt && sed -i "s/^disable_eth=.*/disable_eth=true/" $(OUTPUT_DIR)/uenv.txt || echo "disable_eth=true" >> $(OUTPUT_DIR)/uenv.txt; fi'
	@sed -i "s|\$$(UBOOT_FLASH_CONTROLLER)|$(UBOOT_FLASH_CONTROLLER)|g" $(OUTPUT_DIR)/uenv.txt
	@sh -c '[ "$(SOC_FAMILY)" = "t40" -o "$(SOC_FAMILY)" = "t41" ] && sed -i "s|\$$(UBOOT_NMEM)|nmem=$$\{nmem\} |g" $(OUTPUT_DIR)/uenv.txt || sed -i "s|\$$(UBOOT_NMEM)||g" $(OUTPUT_DIR)/uenv.txt'
	@sh -c '[ "$(SOC_FAMILY)" = "t20" -o "$(SOC_FAMILY)" = "t10" ] && sed -i "s|\$$(UBOOT_ISPMEM)| ispmem=$$\{ispmem\} |g" $(OUTPUT_DIR)/uenv.txt || sed -i "s|\$$(UBOOT_ISPMEM)| |g" $(OUTPUT_DIR)/uenv.txt'
endef
THINGINO_UBOOT_PRE_BUILD_HOOKS += THINGINO_GENERATE_UBOOT_ENV

#
# Patch uboot headers with env data for device if uenv.txt exists
#
define PATCH_DEV_ENV
	$(BR2_EXTERNAL)/scripts/uboot-device-env.sh $(OUTPUT_DIR)/uenv.txt \
		$(@D)/include/configs/isvp_common.h
endef
THINGINO_UBOOT_PRE_BUILD_HOOKS += PATCH_DEV_ENV

#
# Check U-Boot board name (for legacy) or the defconfig/custom config
# file options (for kconfig)
#
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_LEGACY),y)
ifeq ($(THINGINO_UBOOT_BOARD_NAME),)
$(error No U-Boot board name set. Check your BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME setting)
endif # THINGINO_UBOOT_BOARD_NAME
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_KCONFIG),y)
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_USE_DEFCONFIG),y)
ifeq ($(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_BOARD_DEFCONFIG)),)
$(error No board defconfig name specified, check your BR2_PACKAGE_THINGINO_UBOOT_BOARD_DEFCONFIG setting)
endif # qstrip BR2_PACKAGE_THINGINO_UBOOT_BOARD_DEFCONFIG
endif # BR2_PACKAGE_THINGINO_UBOOT_USE_DEFCONFIG
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_USE_CUSTOM_CONFIG),y)
ifeq ($(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_CONFIG_FILE)),)
$(error No board configuration file specified, check your BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_CONFIG_FILE setting)
endif # qstrip BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_CONFIG_FILE
endif # BR2_PACKAGE_THINGINO_UBOOT_USE_CUSTOM_CONFIG
endif # BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_LEGACY

#
# Check custom version option
#
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_VERSION),y)
ifeq ($(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_VERSION_VALUE)),)
$(error No custom U-Boot version specified. Check your BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_VERSION_VALUE setting)
endif # qstrip BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_VERSION_VALUE
endif # BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_VERSION

#
# Check custom tarball option
#
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL),y)
ifeq ($(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL_LOCATION)),)
$(error No custom U-Boot tarball specified. Check your BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL_LOCATION setting)
endif # qstrip BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL_LOCATION
endif # BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_TARBALL

#
# Check Git/Mercurial repo options
#
ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_GIT)$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_HG),y)
ifeq ($(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_URL)),)
$(error No custom U-Boot repository URL specified. Check your BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_URL setting)
endif # qstrip BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_CUSTOM_REPO_URL
ifeq ($(call qstrip,$(BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_VERSION)),)
$(error No custom U-Boot repository version specified. Check your BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_REPO_VERSION setting)
endif # qstrip BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_CUSTOM_REPO_VERSION
endif # BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_GIT || BR2_PACKAGE_THINGINO_UBOOT_CUSTOM_HG

endif # BR2_PACKAGE_THINGINO_UBOOT && BR_BUILDING

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_LEGACY),y)
THINGINO_UBOOT_DEPENDENCIES += \
	$(BR2_BISON_HOST_DEPENDENCY) \
	$(BR2_FLEX_HOST_DEPENDENCY)
$(eval $(generic-package))
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_KCONFIG),y)
THINGINO_UBOOT_MAKE_ENV = $(TARGET_MAKE_ENV)
# Starting with 2021.10, the kconfig in uboot calls the cross-compiler
# to check its capabilities. So we need the toolchain before we can
# call the configurators.
THINGINO_UBOOT_KCONFIG_DEPENDENCIES += \
	toolchain \
	$(BR2_MAKE_HOST_DEPENDENCY) \
	$(BR2_BISON_HOST_DEPENDENCY) \
	$(BR2_FLEX_HOST_DEPENDENCY)
$(eval $(kconfig-package))
endif # BR2_PACKAGE_THINGINO_UBOOT_BUILD_SYSTEM_LEGACY
