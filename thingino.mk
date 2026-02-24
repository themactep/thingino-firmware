$(info --- FILE: thingino.mk)

SIZE_1G := 1073741824
SIZE_512M := 536870912
SIZE_256M := 268435456
SIZE_128M := 134217728
SIZE_32M := 33554432
SIZE_16M := 16777216
SIZE_8M := 8388608

#
# SOC
#

SOC_VENDOR := ingenic

ifeq ($(BR2_SOC_INGENIC_DUMMY),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31x
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T10L),y)
	SOC_FAMILY := t10
	SOC_MODEL := t10l
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T10 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t10_sfcnor_lite"
else ifeq ($(BR2_SOC_INGENIC_T10N),y)
	SOC_FAMILY := t10
	SOC_MODEL := t10n
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T10 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t10_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T10A),y)
	SOC_FAMILY := t10
	SOC_MODEL := t10a
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T10 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t10_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T20L),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20l
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor_lite"
else ifeq ($(BR2_SOC_INGENIC_T20N),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20n
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T20X),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20x
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T20Z),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20z
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21L),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21l
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21N),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21n
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21X),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21x
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21Z),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21zn
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21ZL),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21zl
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T23N),y)
	SOC_FAMILY := t23
	SOC_MODEL := t23n
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T23 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t23n_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T23DL),y)
	SOC_FAMILY := t23
	SOC_MODEL := t23dl
	SOC_RAM_MB := 32
	BR2_SOC_INGENIC_T23 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t23dl_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T23ZN),y)
	SOC_FAMILY := t23
	SOC_MODEL := t23zn
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T23 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t23n_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T30L),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30l
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30_sfcnor_lite"
else ifeq ($(BR2_SOC_INGENIC_T30N),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30n
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T30X),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30x
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T30A),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30a
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30a_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T31L),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31l
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31_sfcnand_lite"
	else
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_lite"
	endif
else ifeq ($(BR2_SOC_INGENIC_T31LC),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31lc
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t31lc_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T31N),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31n
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_t31_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T31X),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31x
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31_sfcnand_ddr128M"
	else
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_ddr128M"
	endif
else ifeq ($(BR2_SOC_INGENIC_T31A),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31a
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31a_sfcnand_ddr128M"
	else
	UBOOT_BOARDNAME := "isvp_t31a_sfcnor_ddr128M"
	endif
else ifeq ($(BR2_SOC_INGENIC_T31AL),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31al
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31al_sfcnand_ddr128M"
	else
	UBOOT_BOARDNAME := "isvp_t31al_sfcnor_ddr128M"
	endif
else ifeq ($(BR2_SOC_INGENIC_T31ZL),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31zl
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31_sfcnand_lite"
	else
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_lite"
	endif
else ifeq ($(BR2_SOC_INGENIC_T31ZX),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31zx
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31_sfcnand_ddr128M"
	else
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_ddr128M"
	endif
else ifeq ($(BR2_SOC_INGENIC_C100),y)
    ifeq ($(KERNEL_VERSION_4),y)
	SOC_FAMILY := c100
	SOC_MODEL := c100
	BR2_SOC_INGENIC_C100 := y
	else
	SOC_FAMILY := t31
	SOC_MODEL := t31x
	BR2_SOC_INGENIC_T31 := y
	endif
	SOC_RAM_MB := 128
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_c100_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_c100_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T40N),y)
	SOC_FAMILY := t40
	SOC_MODEL := t40n
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T40 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t40n_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_t40n_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T40NN),y)
	SOC_FAMILY := t40
	SOC_MODEL := t40nn
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T40 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t40n_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_t40n_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T40XP),y)
	SOC_FAMILY := t40
	SOC_MODEL := t40xp
	SOC_RAM_MB := 256
	BR2_SOC_INGENIC_T40 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t40xp_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_t40xp_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T40A),y)
	SOC_FAMILY := t40
	SOC_MODEL := t40a
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T40 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t40a_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_t40a_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T41LQ),y)
	SOC_FAMILY := t41
	SOC_MODEL := t41lq
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T41 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t41lq_sfc0_nand"
	else
	UBOOT_BOARDNAME := "isvp_t41lq_sfc_nor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T41NQ),y)
	SOC_FAMILY := t41
	SOC_MODEL := t41nq
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T41 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t41nq_sfc0_nand"
	else
	UBOOT_BOARDNAME := "isvp_t41nq_sfc_nor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T41ZL),y)
	SOC_FAMILY := t41
	SOC_MODEL := t41zl
	SOC_RAM_MB := 64
	BR2_SOC_INGENIC_T41 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t41l_sfc0_nand"
	else
	UBOOT_BOARDNAME := "isvp_t41l_sfc_nor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T41ZN),y)
	SOC_FAMILY := t41
	SOC_MODEL := t41zn
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T41 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t41n_sfc0_nand"
	else
	UBOOT_BOARDNAME := "isvp_t41n_sfc_nor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T41ZX),y)
	SOC_FAMILY := t41
	SOC_MODEL := t41zx
	SOC_RAM_MB := 256
	BR2_SOC_INGENIC_T41 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t41zx_sfc0_nand"
	else
	UBOOT_BOARDNAME := "isvp_t41zx_sfc_nor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T41A),y)
	SOC_FAMILY := t41
	SOC_MODEL := t41a
	SOC_RAM_MB := 512
	BR2_SOC_INGENIC_T41 := y
	BR2_XBURST_2 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t41a_sfc0_nand"
	else
	UBOOT_BOARDNAME := "isvp_t41a_sfc_nor"
	endif
else ifeq ($(BR2_SOC_INGENIC_A1N),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1n
	SOC_RAM_MB := 256
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1NT),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1nt
	SOC_RAM_MB := 256
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1X),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1x
	SOC_RAM_MB := 256
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1L),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1l
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1A),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1a
	SOC_RAM_MB := 512
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
endif

SOC_FAMILY_CAPS := $(shell echo $(SOC_FAMILY) | tr a-z A-Z)
SOC_MODEL_LESS_Z := $(subst z,,$(SOC_MODEL))

ifeq ($(BR2_XBURST_1),y)
	INGENIC_ARCH := xburst1
else ifeq ($(BR2_XBURST_2),y)
	INGENIC_ARCH := xburst2
else
	INGENIC_ARCH := xburst1
endif

export BR2_SOC_INGENIC_A1
export BR2_SOC_INGENIC_T10
export BR2_SOC_INGENIC_T20
export BR2_SOC_INGENIC_T21
export BR2_SOC_INGENIC_T30
export BR2_SOC_INGENIC_T31
export BR2_SOC_INGENIC_T40
export BR2_SOC_INGENIC_T41
export BR2_SOC_INGENIC_C100
export BR2_XBURST_1
export BR2_XBURST_2
export INGENIC_ARCH
export SOC_VENDOR
export SOC_FAMILY
export SOC_FAMILY_CAPS
export SOC_MODEL
export SOC_MODEL_LESS_Z
export SOC_RAM_MB

#
# KERNEL
#

# default to older kernel if none set
ifneq ($(KERNEL_VERSION_3)$(KERNEL_VERSION_4),y)
	ifeq ($(BR2_SOC_INGENIC_T41),y)
		KERNEL_VERSION_4 := y
	else ifeq ($(BR2_SOC_INGENIC_T40)$(BR2_SOC_INGENIC_A1),y)
		KERNEL_VERSION_4 := y
	else
		KERNEL_VERSION_3 := y
	endif
endif

ifeq ($(BR2_SOC_INGENIC_T41),y)
	ifeq ($(KERNEL_VERSION_3),y)
		KERNEL_VERSION := 3.10
		KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
		KERNEL_BRANCH := ingenic-t41-3.10.14
	else
		KERNEL_VERSION := 4.4
		KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
		KERNEL_BRANCH := ingenic-t41-4.4.94
	endif
else ifeq ($(BR2_SOC_INGENIC_T40),y)
	KERNEL_VERSION := 4.4
	KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
	KERNEL_BRANCH := ingenic-t40
else ifeq ($(BR2_SOC_INGENIC_A1),y)
	KERNEL_VERSION := 4.4
	KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
	KERNEL_BRANCH := ingenic-a1
else ifeq ($(BR2_SOC_INGENIC_T31),y)
	ifeq ($(KERNEL_VERSION_3),y)
		KERNEL_VERSION := 3.10
		KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
		KERNEL_BRANCH := ingenic-t31
	else ifeq ($(KERNEL_VERSION_4),y)
		KERNEL_VERSION := 4.4
		KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
		KERNEL_BRANCH := ingenic-t31-4.4.94
		#KERNEL_SITE := https://github.com/matteius/ingenic-t31-zrt-kernel-4.4.94
		#KERNEL_BRANCH := stable
	endif
else ifeq ($(BR2_SOC_INGENIC_C100),y)
	ifeq ($(KERNEL_VERSION_3),y)
		KERNEL_VERSION := 3.10
		KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
		KERNEL_BRANCH := ingenic-t31
	else ifeq ($(KERNEL_VERSION_4),y)
		KERNEL_VERSION := 4.4
		KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
		KERNEL_BRANCH := ingenic-t31-4.4.94
	endif
else
	KERNEL_VERSION := 3.10
	KERNEL_SITE := https://github.com/gtxaspec/thingino-linux
	KERNEL_BRANCH := ingenic-t31
endif

KERNEL_HASH := $(shell git ls-remote $(KERNEL_SITE) $(KERNEL_BRANCH) | head -1 | cut -f1)
KERNEL_TARBALL_URL := $(KERNEL_SITE)/archive/$(KERNEL_HASH).tar.gz

export KERNEL_BRANCH
export KERNEL_HASH
export KERNEL_SITE
export KERNEL_TARBALL_URL
export KERNEL_VERSION
export KERNEL_VERSION_3
export KERNEL_VERSION_4

#
# IMAGE SENSOR
#

SENSOR_1_MODEL = $(strip $(subst ",,$(BR2_SENSOR_1_NAME)))
SENSOR_2_MODEL = $(strip $(subst ",,$(BR2_SENSOR_2_NAME)))
SENSOR_3_MODEL = $(strip $(subst ",,$(BR2_SENSOR_3_NAME)))
SENSOR_4_MODEL = $(strip $(subst ",,$(BR2_SENSOR_4_NAME)))

# Filter out "none" values
ifeq ($(SENSOR_1_MODEL),none)
SENSOR_1_MODEL :=
endif
ifeq ($(SENSOR_2_MODEL),none)
SENSOR_2_MODEL :=
endif
ifeq ($(SENSOR_3_MODEL),none)
SENSOR_3_MODEL :=
endif
ifeq ($(SENSOR_4_MODEL),none)
SENSOR_4_MODEL :=
endif

SENSOR_1_PARAMS := $(call qstrip,$(BR2_SENSOR_1_PARAMS))
SENSOR_2_PARAMS := $(call qstrip,$(BR2_SENSOR_2_PARAMS))
SENSOR_3_PARAMS := $(call qstrip,$(BR2_SENSOR_3_PARAMS))
SENSOR_4_PARAMS := $(call qstrip,$(BR2_SENSOR_4_PARAMS))

export SENSOR_1_MODEL
export SENSOR_2_MODEL
export SENSOR_3_MODEL
export SENSOR_4_MODEL

export SENSOR_1_PARAMS
export SENSOR_2_PARAMS
export SENSOR_3_PARAMS
export SENSOR_4_PARAMS

#
# ISP
#

# ISP kernel reserved memory allocations
FOUND_RMEM_MB := $(BR2_THINGINO_RMEM_MB)

# Set the default RMEM size based on SOC ram size if no explicit value found
# These values match the default values found in uboot by the soc ram size
# Default values should match what's in Config.soc.in since we can't use the BR2 variables directly
ifeq ($(FOUND_RMEM_MB),)
	ifeq ($(SOC_RAM_MB),64)
		ISP_RMEM_MB := 23
	else ifeq ($(SOC_RAM_MB),128)
		ISP_RMEM_MB := 29
	else ifeq ($(SOC_RAM_MB),256)
		ISP_RMEM_MB := 64
	else
		ISP_RMEM_MB := 32
	endif
else
	ISP_RMEM_MB := $(FOUND_RMEM_MB)
endif
export ISP_RMEM_MB

FOUND_ISPMEM_MB := $(BR2_THINGINO_ISPMEM_MB)
ifeq ($(FOUND_ISPMEM_MB),)
	ISP_ISPMEM_MB := 8
else
	ISP_ISPMEM_MB := $(FOUND_ISPMEM_MB)
endif
export ISP_ISPMEM_MB

FOUND_NMEM_MB := $(BR2_THINGINO_NMEM_MB)
ifeq ($(FOUND_NMEM_MB),)
	ifeq ($(SOC_RAM_MB),64)
		ISP_NMEM_MB := 23
	else ifeq ($(SOC_RAM_MB),128)
		ISP_NMEM_MB := 29
	else ifeq ($(SOC_RAM_MB),256)
		ISP_NMEM_MB := 64
	else
		ISP_NMEM_MB := 16
	endif
else
	ISP_NMEM_MB := $(FOUND_NMEM_MB)
endif
export ISP_NMEM_MB

# Default IPU clock speed
ifeq ($(BR2_IPU_CLK_SCLKA),y)
	IPU_CLK_SRC := clk_name=sclka
else ifeq ($(BR2_IPU_CLK_VPLL),y)
	IPU_CLK_SRC := clk_name=vpll
else ifeq ($(BR2_IPU_CLK_MPLL),y)
	IPU_CLK_SRC := clk_name=mpll
else ifeq ($(BR2_IPU_CLK_INTERNAL),y)
	IPU_CLK_SRC :=
else
	IPU_CLK_SRC :=
endif

ifeq ($(BR2_IPU_CLK_400MHZ),y)
	IPU_CLK := ipu_clk=400000000
else ifeq ($(BR2_IPU_CLK_450MHZ),y)
	IPU_CLK := ipu_clk=450000000
else ifeq ($(BR2_IPU_CLK_500MHZ),y)
	IPU_CLK := ipu_clk=500000000
else ifeq ($(BR2_IPU_CLK_550MHZ),y)
	IPU_CLK := ipu_clk=550000000
else ifeq ($(BR2_IPU_CLK_600MHZ),y)
	IPU_CLK := ipu_clk=600000000
else ifeq ($(BR2_IPU_CLK_650MHZ),y)
	IPU_CLK := ipu_clk=650000000
else
	IPU_CLK :=
endif

ifeq ($(BR2_AVPU_APLL),y)
	AVPU_CLK_SRC := clk_name=apll
else ifeq ($(BR2_AVPU_MPLL),y)
	AVPU_CLK_SRC := clk_name=mpll
else ifeq ($(BR2_AVPU_VPLL),y)
	AVPU_CLK_SRC := clk_name=vpll
else ifeq ($(BR2_AVPU_INTERNAL),y)
	AVPU_CLK_SRC :=
else
	AVPU_CLK_SRC :=
endif

ifeq ($(BR2_AVPU_CLK_400MHZ),y)
	AVPU_CLK := avpu_clk=400000000
else ifeq ($(BR2_AVPU_CLK_450MHZ),y)
	AVPU_CLK := avpu_clk=450000000
else ifeq ($(BR2_AVPU_CLK_500MHZ),y)
	AVPU_CLK := avpu_clk=500000000
else ifeq ($(BR2_AVPU_CLK_550MHZ),y)
	AVPU_CLK := avpu_clk=550000000
else ifeq ($(BR2_AVPU_CLK_600MHZ),y)
	AVPU_CLK := avpu_clk=600000000
else ifeq ($(BR2_AVPU_CLK_650MHZ),y)
	AVPU_CLK := avpu_clk=650000000
else ifeq ($(BR2_AVPU_CLK_700MHZ),y)
	AVPU_CLK := avpu_clk=700000000
else
	AVPU_CLK :=
endif

# Default ISP clock speed
ifeq ($(BR2_ISP_CLK_SCLKA),y)
	ISP_CLK_SRC := clk_name=sclka
else ifeq ($(BR2_ISP_CLK_VPLL),y)
	ISP_CLK_SRC := clk_name=vpll
else ifeq ($(BR2_ISP_CLK_MPLL),y)
	ISP_CLK_SRC := clk_name=mpll
else ifeq ($(BR2_ISP_CLK_INTERNAL),y)
	ISP_CLK_SRC :=
else
	ISP_CLK_SRC :=
endif

ifeq ($(BR2_ISP_CLK_90MHZ),y)
	ISP_CLK := isp_clk=90000000
else ifeq ($(BR2_ISP_CLK_100MHZ),y)
	ISP_CLK := isp_clk=100000000
else ifeq ($(BR2_ISP_CLK_120MHZ),y)
	ISP_CLK := isp_clk=120000000
else ifeq ($(BR2_ISP_CLK_125MHZ),y)
	ISP_CLK := isp_clk=125000000
else ifeq ($(BR2_ISP_CLK_150MHZ),y)
	ISP_CLK := isp_clk=150000000
else ifeq ($(BR2_ISP_CLK_175MHZ),y)
	ISP_CLK := isp_clk=175000000
else ifeq ($(BR2_ISP_CLK_200MHZ),y)
	ISP_CLK := isp_clk=200000000
else ifeq ($(BR2_ISP_CLK_220MHZ),y)
	ISP_CLK := isp_clk=220000000
else ifeq ($(BR2_ISP_CLK_225MHZ),y)
	ISP_CLK := isp_clk=225000000
else ifeq ($(BR2_ISP_CLK_250MHZ),y)
	ISP_CLK := isp_clk=250000000
else ifeq ($(BR2_ISP_CLK_300MHZ),y)
	ISP_CLK := isp_clk=300000000
else ifeq ($(BR2_ISP_CLK_350MHZ),y)
	ISP_CLK := isp_clk=350000000
else
	ISP_CLK :=
endif

ifeq ($(BR2_ISP_CLKA_SCLKA),y)
	ISP_CLKA_CLK_SRC := clka_name=sclka
else ifeq ($(BR2_ISP_CLKA_INTERNAL),y)
        ISP_CLKA_CLK_SRC :=
else
	ISP_CLKA_CLK_SRC :=
endif

ifeq ($(BR2_ISP_CLKA_400MHZ),y)
	ISP_CLKA_CLK := isp_clka=400000000
else ifeq ($(BR2_ISP_CLKA_450MHZ),y)
	ISP_CLKA_CLK := isp_clka=450000000
else ifeq ($(BR2_ISP_CLKA_500MHZ),y)
	ISP_CLKA_CLK := isp_clka=500000000
else ifeq ($(BR2_ISP_CLKA_550MHZ),y)
	ISP_CLKA_CLK := isp_clka=550000000
else ifeq ($(BR2_ISP_CLKA_600MHZ),y)
	ISP_CLKA_CLK := isp_clka=600000000
else ifeq ($(BR2_ISP_CLKA_650MHZ),y)
	ISP_CLKA_CLK := isp_clka=650000000
else ifeq ($(BR2_ISP_CLKA_700MHZ),y)
	ISP_CLKA_CLK := isp_clka=700000000
else
	ISP_CLKA_CLK :=
endif

ifeq ($(BR2_ISP_CLKS_SCLKA),y)
	ISP_CLKS_CLK_SRC := clks_name=sclka
else ifeq ($(BR2_ISP_CLKS_VPLL),y)
	ISP_CLKS_CLK_SRC := clks_name=vpll
else ifeq ($(BR2_ISP_CLKS_MPLL),y)
	ISP_CLKS_CLK_SRC := clks_name=mpll
else ifeq ($(BR2_ISP_CLKS_INTERNAL),y)
        ISP_CLKS_CLK_SRC :=
else
	ISP_CLKS_CLK_SRC :=
endif

ifeq ($(BR2_ISP_CLKS_400MHZ),y)
	ISP_CLKS_CLK := isp_clks=400000000
else ifeq ($(BR2_ISP_CLKS_450MHZ),y)
	ISP_CLKS_CLK := isp_clks=450000000
else ifeq ($(BR2_ISP_CLKS_500MHZ),y)
	ISP_CLKS_CLK := isp_clks=500000000
else ifeq ($(BR2_ISP_CLKS_550MHZ),y)
	ISP_CLKS_CLK := isp_clks=550000000
else ifeq ($(BR2_ISP_CLKS_600MHZ),y)
	ISP_CLKS_CLK := isp_clks=600000000
else ifeq ($(BR2_ISP_CLKS_650MHZ),y)
	ISP_CLKS_CLK := isp_clks=650000000
else ifeq ($(BR2_ISP_CLKS_700MHZ),y)
	ISP_CLKS_CLK := isp_clks=700000000
else
	ISP_CLKS_CLK :=
endif

ifeq ($(BR2_ISP_MEMOPT_0),y)
	ISP_MEMOPT :=
else ifeq ($(BR2_ISP_MEMOPT_1),y)
	ISP_MEMOPT := isp_memopt=1
else ifeq ($(BR2_ISP_MEMOPT_2),y)
	ISP_MEMOPT := isp_memopt=2
else ifeq ($(BR2_ISP_MEMOPT_3),y)
	ISP_MEMOPT := isp_memopt=3
else
ifneq ($(SOC_RAM_MB),)
ifeq ($(shell test $(SOC_RAM_MB) -le 64 && ! echo "$(SOC_FAMILY)" | grep -Eq "t10|t20|t21|t30" && echo true),true)
	ISP_MEMOPT := isp_memopt=1
else
	ISP_MEMOPT :=
endif
endif
endif

ifeq ($(BR2_ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM),y)
	ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM := isp_day_night_switch_drop_frame_num=$(BR2_ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM_VALUE)
else
	ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM :=
endif

ifeq ($(BR2_ISP_CH0_PRE_DEQUEUE_TIME),y)
	ISP_CH0_PRE_DEQUEUE_TIME := isp_ch0_pre_dequeue_time=$(BR2_ISP_CH0_PRE_DEQUEUE_TIME_VALUE)
else
	ISP_CH0_PRE_DEQUEUE_TIME :=
endif

ifeq ($(BR2_ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS),y)
	ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS := isp_ch0_pre_dequeue_interrupt_process=$(BR2_ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS_VALUE)
else
	ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS :=
endif

ifeq ($(BR2_ISP_CH0_PRE_DEQUEUE_VALID_LINES),y)
	ISP_CH0_PRE_DEQUEUE_VALID_LINES := isp_ch0_pre_dequeue_valid_lines=$(BR2_ISP_CH0_PRE_DEQUEUE_VALID_LINES_VALUE)
else
	ISP_CH0_PRE_DEQUEUE_VALID_LINES :=
endif

ifeq ($(BR2_ISP_CH1_DEQUEUE_DELAY_TIME),y)
	ISP_CH1_DEQUEUE_DELAY_TIME := isp_ch1_dequeue_delay_time=$(BR2_ISP_CH1_DEQUEUE_DELAY_TIME_VALUE)
else
	ISP_CH1_DEQUEUE_DELAY_TIME :=
endif

ifeq ($(BR2_ISP_MIPI_SWITCH_GPIO),y)
	ISP_MIPI_SWITCH_GPIO := mipi_switch_gpio=$(BR2_ISP_MIPI_SWITCH_GPIO)
else
	ISP_MIPI_SWITCH_GPIO :=
endif

ifeq ($(BR2_ISP_DIRECT_MODE_0),y)
	ISP_DIRECT_MODE := direct_mode=0
else ifeq ($(BR2_ISP_DIRECT_MODE_1),y)
	ISP_DIRECT_MODE := direct_mode=1
else ifeq ($(BR2_ISP_DIRECT_MODE_2),y)
	ISP_DIRECT_MODE := direct_mode=2
else
	ISP_DIRECT_MODE := direct_mode=0
endif

ifeq ($(BR2_ISP_IVDC_MEM_LINE),y)
	ISP_IVDC_MEM_LINE := ivdc_mem_line=$(BR2_ISP_IVDC_MEM_LINE_VALUE)
else
	ISP_IVDC_MEM_LINE :=
endif

ifeq ($(BR2_ISP_IVDC_THRESHOLD_LINE),y)
	ISP_IVDC_THRESHOLD_LINE := ivdc_threshold_line=$(BR2_ISP_IVDC_THRESHOLD_LINE_VALUE)
else
	ISP_IVDC_THRESHOLD_LINE :=
endif

ifeq ($(BR2_ISP_CONFIG_HZ),y)
	ISP_CONFIG_HZ := isp_config_hz=$(BR2_ISP_CONFIG_HZ_VALUE)
else
	ISP_CONFIG_HZ :=
endif

ifeq ($(BR2_ISP_PRINT_LEVEL_0),y)
	ISP_PRINT_LEVEL := print_level=0
else ifeq ($(BR2_ISP_PRINT_LEVEL_1),y)
	ISP_PRINT_LEVEL := print_level=1
else ifeq ($(BR2_ISP_PRINT_LEVEL_2),y)
	ISP_PRINT_LEVEL := print_level=2
else ifeq ($(BR2_ISP_PRINT_LEVEL_3),y)
	ISP_PRINT_LEVEL := print_level=3
else
	ifeq ($(shell echo "$(SOC_FAMILY)" | grep -Eq "t10|t20|t21" && echo true),true)
		ISP_PRINT_LEVEL :=
	else
		ISP_PRINT_LEVEL := print_level=1
	endif
endif

ifeq ($(BR2_ISP_ISPW),y)
	ISP_ISPW := ispw=$(BR2_ISP_ISPW_VALUE)
else
	ISP_ISPW :=
endif

ifeq ($(BR2_ISP_ISPH),y)
	ISP_ISPH := isph=$(BR2_ISP_ISPH_VALUE)
else
	ISP_ISPH :=
endif

ifeq ($(BR2_ISP_ISPTOP),y)
	ISP_ISPTOP := isptop=$(BR2_ISP_ISPTOP_VALUE)
else
	ISP_ISPTOP :=
endif

ifeq ($(BR2_ISP_ISPLEFT),y)
	ISP_ISPLEFT := ispleft=$(BR2_ISP_ISPLEFT_VALUE)
else
	ISP_ISPLEFT :=
endif

ifeq ($(BR2_ISP_ISPCROP),y)
	ISP_ISPCROP := ispcrop=$(BR2_ISP_ISPCROP_VALUE)
else
	ISP_ISPCROP :=
endif

ifeq ($(BR2_ISP_ISPCROPWH),y)
	ISP_ISPCROPWH := ispcropwh=$(BR2_ISP_ISPCROPWH_VALUE)
else
	ISP_ISPCROPWH :=
endif

ifeq ($(BR2_ISP_ISPCROPTL),y)
	ISP_ISPCROPTL := ispcroptl=$(BR2_ISP_ISPCROPTL_VALUE)
else
	ISP_ISPCROPTL :=
endif

ifeq ($(BR2_ISP_ISPSCALER),y)
	ISP_ISPSCALER := isp_scaler=$(BR2_ISP_ISPSCALER_VALUE)
else
	ISP_ISPSCALER :=
endif

ifeq ($(BR2_ISP_ISPSCALERWH),y)
	ISP_ISPSCALERWH := isp_scalerwh=$(BR2_ISP_ISPSCALERWH_VALUE)
else
	ISP_ISPSCALERWH :=
endif

ifeq ($(BR2_ISP_ISP_M1_BUFS),y)
	ISP_ISP_M1_BUFS := isp_m1_bufs=$(BR2_ISP_ISP_M1_BUFS_VALUE)
else
	ISP_ISP_M1_BUFS :=
endif

ifeq ($(BR2_ISP_ISP_M2_BUFS),y)
	ISP_ISP_M2_BUFS := isp_m2_bufs=$(BR2_ISP_ISP_M2_BUFS_VALUE)
else
	ISP_ISP_M2_BUFS :=
endif


export AVPU_CLK_SRC
export AVPU_CLK
export IPU_CLK_SRC
export IPU_CLK
export ISP_CLK_SRC
export ISP_CLK
export ISP_CLKA_CLK_SRC
export ISP_CLKA_CLK
export ISP_CLKS_CLK_SRC
export ISP_CLKS_CLK

export ISP_MEMOPT
export ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM
export ISP_CH0_PRE_DEQUEUE_TIME
export ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS
export ISP_CH0_PRE_DEQUEUE_VALID_LINES
export ISP_CH1_DEQUEUE_DELAY_TIME
export ISP_MIPI_SWITCH_GPIO
export ISP_DIRECT_MODE
export ISP_IVDC_MEM_LINE
export ISP_IVDC_THRESHOLD_LINE
export ISP_CONFIG_HZ
export ISP_PRINT_LEVEL
export ISP_ISPW
export ISP_ISPH
export ISP_ISPTOP
export ISP_ISPLEFT
export ISP_ISPCROP
export ISP_ISPCROPWH
export ISP_ISPCROPTL
export ISP_ISPSCALER
export ISP_ISPSCALERWH
export ISP_ISP_M1_BUFS
export ISP_ISP_M2_BUFS

#
# FLASH CHIP
#

ifeq ($(FLASH_SIZE_MB),)
	FLASH_SIZE_MB := 8
endif
export FLASH_SIZE_MB

#
# U-BOOT
#

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME),)
	BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME := $(UBOOT_BOARDNAME)
endif

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME),)
	BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME := "u-boot-lzo-with-spl.bin"
endif

UBOOT_REPO := https://github.com/gtxaspec/ingenic-u-boot-$(INGENIC_ARCH)

ifeq ($(BR2_SOC_INGENIC_T40),y)
	UBOOT_REPO_BRANCH := t40
else ifeq ($(BR2_SOC_INGENIC_T41),y)
	UBOOT_REPO_BRANCH := t41
else ifeq ($(BR2_SOC_INGENIC_A1),y)
	UBOOT_REPO_BRANCH := a1
else
	UBOOT_REPO_BRANCH := master
endif

UBOOT_REPO_VERSION := $(shell git ls-remote $(UBOOT_REPO) $(UBOOT_REPO_BRANCH) | head -1 | cut -f1)

export UBOOT_BOARDNAME
export UBOOT_REPO
export UBOOT_REPO_BRANCH
export UBOOT_REPO_VERSION
export BR2_PACKAGE_THINGINO_UBOOT_BOARDNAME
export BR2_PACKAGE_THINGINO_UBOOT_FORMAT_CUSTOM_NAME

#
# STREAMER
#

ifeq ($(BR2_PACKAGE_RAPTOR_IPC),y)
	STREAMER := raptor
else ifeq ($(BR2_PACKAGE_PRUDYNT_T),y)
	STREAMER := prudynt
else
	STREAMER := prudynt
endif

export STREAMER

export BR2_THINGINO_MOTORS
export BR2_THINGINO_MOTORS_SPI
export BR2_THINGINO_MOTORS_TCU
export BR2_THINGINO_SINFO

export BR2_THINGINO_DEVICE_TYPE_DOORBELL
export BR2_THINGINO_DEVICE_TYPE_IPCAM
export BR2_THINGINO_DEVICE_TYPE_IPCAM_PAN_TILT
export BR2_THINGINO_DEVICE_TYPE_IPCAM_PAN_TILT_ZOOM
export BR2_THINGINO_DEVICE_TYPE_WEBCAM
