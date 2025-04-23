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
	SOC_RAM := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T10L),y)
	SOC_FAMILY := t10
	SOC_MODEL := t10l
	SOC_RAM := 64
	BR2_SOC_INGENIC_T10 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t10_sfcnor_lite"
else ifeq ($(BR2_SOC_INGENIC_T10N),y)
	SOC_FAMILY := t10
	SOC_MODEL := t10n
	SOC_RAM := 64
	BR2_SOC_INGENIC_T10 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t10_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T10A),y)
	SOC_FAMILY := t10
	SOC_MODEL := t10a
	SOC_RAM := 64
	BR2_SOC_INGENIC_T10 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t10_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T20L),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20l
	SOC_RAM := 64
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor_lite"
else ifeq ($(BR2_SOC_INGENIC_T20N),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20n
	SOC_RAM := 64
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T20X),y)
	SOC_FAMILY := t20
	SOC_MODEL := t20x
	SOC_RAM := 128
	BR2_SOC_INGENIC_T20 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t20_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T21L),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21l
	SOC_RAM := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21N),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21n
	SOC_RAM := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21X),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21x
	SOC_RAM := 128
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21Z),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21zn
	SOC_RAM := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T21ZL),y)
	SOC_FAMILY := t21
	SOC_MODEL := t21zl
	SOC_RAM := 64
	BR2_SOC_INGENIC_T21 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t21_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T23N),y)
	SOC_FAMILY := t23
	SOC_MODEL := t23n
	SOC_RAM := 64
	BR2_SOC_INGENIC_T23 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t23n_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T23ZN),y)
	SOC_FAMILY := t23
	SOC_MODEL := t23zn
	SOC_RAM := 64
	BR2_SOC_INGENIC_T23 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t23n_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T30L),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30l
	SOC_RAM := 64
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30_sfcnor_lite"
else ifeq ($(BR2_SOC_INGENIC_T30N),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30n
	SOC_RAM := 64
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T30X),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30x
	SOC_RAM := 128
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T30A),y)
	SOC_FAMILY := t30
	SOC_MODEL := t30a
	SOC_RAM := 128
	BR2_SOC_INGENIC_T30 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t30a_sfcnor_ddr128M"
else ifeq ($(BR2_SOC_INGENIC_T31L),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31l
	SOC_RAM := 64
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
	SOC_RAM := 64
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t31lc_sfcnor"
else ifeq ($(BR2_SOC_INGENIC_T31N),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31n
	SOC_RAM := 64
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
	SOC_RAM := 128
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
	SOC_RAM := 128
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
	SOC_RAM := 128
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
	SOC_RAM := 64
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
	SOC_RAM := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_t31_sfcnand_ddr128M"
	else
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_ddr128M"
	endif
else ifeq ($(BR2_SOC_INGENIC_C100),y)
	SOC_FAMILY := c100
	SOC_MODEL := c100
	SOC_RAM := 128
	BR2_SOC_INGENIC_C100 := y
	BR2_XBURST_1 := y
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	UBOOT_BOARDNAME := "isvp_c100_sfcnand"
	else
	UBOOT_BOARDNAME := "isvp_c100_sfcnor"
	endif
else ifeq ($(BR2_SOC_INGENIC_T40N),y)
	SOC_FAMILY := t40
	SOC_MODEL := t40n
	SOC_RAM := 128
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
	SOC_RAM := 128
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
	SOC_RAM := 256
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
	SOC_RAM := 128
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
	SOC_RAM := 64
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
	SOC_RAM := 128
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
	SOC_RAM := 64
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
	SOC_RAM := 128
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
	SOC_RAM := 256
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
	SOC_RAM := 512
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
	SOC_RAM := 256
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1NT),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1nt
	SOC_RAM := 256
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1X),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1x
	SOC_RAM := 256
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1L),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1l
	SOC_RAM := 128
	BR2_SOC_INGENIC_A1 := y
	BR2_XBURST_2 := y
	UBOOT_BOARDNAME := "isvp_a1_all_lzma_sfc0nor"
else ifeq ($(BR2_SOC_INGENIC_A1A),y)
	SOC_FAMILY := a1
	SOC_MODEL := a1a
	SOC_RAM := 512
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
export SOC_RAM

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

ifeq ($(BR2_SENSOR_DUMMY),y)
	SENSOR_MODEL :=
else ifeq ($(BR2_SENSOR_AR1337),y)
	SENSOR_MODEL := ar1337
else ifeq ($(BR2_SENSOR_BF3A03),y)
	SENSOR_MODEL := bf3a03
else ifeq ($(BR2_SENSOR_C2399),y)
	SENSOR_MODEL := c2399
else ifeq ($(BR2_SENSOR_C23A98),y)
	SENSOR_MODEL := c23a98
else ifeq ($(BR2_SENSOR_C3390),y)
	SENSOR_MODEL := c3390
else ifeq ($(BR2_SENSOR_C4390),y)
	SENSOR_MODEL := c4390
else ifeq ($(BR2_SENSOR_CV2001),y)
	SENSOR_MODEL := cv2001
else ifeq ($(BR2_SENSOR_CV3001),y)
	SENSOR_MODEL := cv3001
else ifeq ($(BR2_SENSOR_CV4001),y)
	SENSOR_MODEL := cv4001
else ifeq ($(BR2_SENSOR_GC0328),y)
	SENSOR_MODEL := gc0328
else ifeq ($(BR2_SENSOR_GC032A),y)
	SENSOR_MODEL := gc032a
else ifeq ($(BR2_SENSOR_GC1034),y)
	SENSOR_MODEL := gc1034
else ifeq ($(BR2_SENSOR_GC1054),y)
	SENSOR_MODEL := gc1054
else ifeq ($(BR2_SENSOR_GC1084),y)
	SENSOR_MODEL := gc1084
else ifeq ($(BR2_SENSOR_GC2023),y)
	SENSOR_MODEL := gc2023
else ifeq ($(BR2_SENSOR_GC2033),y)
	SENSOR_MODEL := gc2033
else ifeq ($(BR2_SENSOR_GC2053),y)
	SENSOR_MODEL := gc2053
else ifeq ($(BR2_SENSOR_GC2063),y)
	SENSOR_MODEL := gc2063
else ifeq ($(BR2_SENSOR_GC2083),y)
	SENSOR_MODEL := gc2083
else ifeq ($(BR2_SENSOR_GC2093),y)
	SENSOR_MODEL := gc2093
else ifeq ($(BR2_SENSOR_GC3003),y)
	SENSOR_MODEL := gc3003
else ifeq ($(BR2_SENSOR_GC3003A),y)
	SENSOR_MODEL := gc3003a
else ifeq ($(BR2_SENSOR_GC4023),y)
	SENSOR_MODEL := gc4023
else ifeq ($(BR2_SENSOR_GC4653),y)
	SENSOR_MODEL := gc4653
else ifeq ($(BR2_SENSOR_GC4C33),y)
	SENSOR_MODEL := gc4c33
else ifeq ($(BR2_SENSOR_GC5035),y)
	SENSOR_MODEL := gc5035
else ifeq ($(BR2_SENSOR_GC5603),y)
	SENSOR_MODEL := gc5603
else ifeq ($(BR2_SENSOR_GC8023),y)
	SENSOR_MODEL := gc8023
else ifeq ($(BR2_SENSOR_IMX298),y)
	SENSOR_MODEL := imx298
else ifeq ($(BR2_SENSOR_IMX307),y)
	SENSOR_MODEL := imx307
else ifeq ($(BR2_SENSOR_IMX327),y)
	SENSOR_MODEL := imx327
else ifeq ($(BR2_SENSOR_IMX335),y)
	SENSOR_MODEL := imx335
else ifeq ($(BR2_SENSOR_IMX664),y)
	SENSOR_MODEL := imx664
else ifeq ($(BR2_SENSOR_JXF22),y)
	SENSOR_MODEL := jxf22
else ifeq ($(BR2_SENSOR_JXF23),y)
	SENSOR_MODEL := jxf23
else ifeq ($(BR2_SENSOR_JXF28P),y)
	SENSOR_MODEL := jxf28p
else ifeq ($(BR2_SENSOR_JXF32),y)
	SENSOR_MODEL := jxf32
else ifeq ($(BR2_SENSOR_JXF35),y)
	SENSOR_MODEL := jxf35
else ifeq ($(BR2_SENSOR_JXF352),y)
	SENSOR_MODEL := jxf352
else ifeq ($(BR2_SENSOR_JXF355P),y)
	SENSOR_MODEL := jxf355p
else ifeq ($(BR2_SENSOR_JXF37),y)
	SENSOR_MODEL := jxf37
else ifeq ($(BR2_SENSOR_JXF37P),y)
	SENSOR_MODEL := jxf37p
else ifeq ($(BR2_SENSOR_JXF38P),y)
	SENSOR_MODEL := jxf38p
else ifeq ($(BR2_SENSOR_JXF51),y)
	SENSOR_MODEL := jxf51
else ifeq ($(BR2_SENSOR_JXF53),y)
	SENSOR_MODEL := jxf53
else ifeq ($(BR2_SENSOR_JXH42),y)
	SENSOR_MODEL := jxh42
else ifeq ($(BR2_SENSOR_JXH61P),y)
	SENSOR_MODEL := jxh61p
else ifeq ($(BR2_SENSOR_JXH62),y)
	SENSOR_MODEL := jxh62
else ifeq ($(BR2_SENSOR_JXH63),y)
	SENSOR_MODEL := jxh63
else ifeq ($(BR2_SENSOR_JXH63P),y)
	SENSOR_MODEL := jxh63p
else ifeq ($(BR2_SENSOR_JXH66),y)
	SENSOR_MODEL := jxh66
else ifeq ($(BR2_SENSOR_JXK03),y)
	SENSOR_MODEL := jxk03
else ifeq ($(BR2_SENSOR_JXK04),y)
	SENSOR_MODEL := jxk04
else ifeq ($(BR2_SENSOR_JXK05),y)
	SENSOR_MODEL := jxk05
else ifeq ($(BR2_SENSOR_JXK06),y)
	SENSOR_MODEL := jxk06
else ifeq ($(BR2_SENSOR_JXQ03),y)
	SENSOR_MODEL := jxq03
else ifeq ($(BR2_SENSOR_JXQ03P),y)
	SENSOR_MODEL := jxq03p
else ifeq ($(BR2_SENSOR_MIS2006),y)
	SENSOR_MODEL := mis2006
else ifeq ($(BR2_SENSOR_MIS2008),y)
	SENSOR_MODEL := mis2008
else ifeq ($(BR2_SENSOR_MIS4001),y)
	SENSOR_MODEL := mis4001
else ifeq ($(BR2_SENSOR_MIS5001),y)
	SENSOR_MODEL := mis5001
else ifeq ($(BR2_SENSOR_OS02B10),y)
	SENSOR_MODEL := os02b10
else ifeq ($(BR2_SENSOR_OS02D20),y)
	SENSOR_MODEL := os02d20
else ifeq ($(BR2_SENSOR_OS02G10),y)
	SENSOR_MODEL := os02g10
else ifeq ($(BR2_SENSOR_OS02K10),y)
	SENSOR_MODEL := os02k10
else ifeq ($(BR2_SENSOR_OS03B10),y)
	SENSOR_MODEL := os03b10
else ifeq ($(BR2_SENSOR_OS04B10),y)
	SENSOR_MODEL := os04b10
else ifeq ($(BR2_SENSOR_OS04C10),y)
	SENSOR_MODEL := os04c10
else ifeq ($(BR2_SENSOR_OS04L10),y)
	SENSOR_MODEL := os04l10
else ifeq ($(BR2_SENSOR_OS05A10),y)
	SENSOR_MODEL := os05a10
else ifeq ($(BR2_SENSOR_OS05A20),y)
	SENSOR_MODEL := os05a20
else ifeq ($(BR2_SENSOR_OV2735B),y)
	SENSOR_MODEL := ov2735b
else ifeq ($(BR2_SENSOR_OV2740),y)
	SENSOR_MODEL := ov2740
else ifeq ($(BR2_SENSOR_OV2745),y)
	SENSOR_MODEL := ov2745
else ifeq ($(BR2_SENSOR_OV5648),y)
	SENSOR_MODEL := ov5648
else ifeq ($(BR2_SENSOR_OV5695),y)
	SENSOR_MODEL := ov5695
else ifeq ($(BR2_SENSOR_OV8856),y)
	SENSOR_MODEL := ov8856
else ifeq ($(BR2_SENSOR_OV9712),y)
	SENSOR_MODEL := ov9712
else ifeq ($(BR2_SENSOR_OV9732),y)
	SENSOR_MODEL := ov9732
else ifeq ($(BR2_SENSOR_OV9750),y)
	SENSOR_MODEL := ov9750
else ifeq ($(BR2_SENSOR_PS5258),y)
	SENSOR_MODEL := ps5258
else ifeq ($(BR2_SENSOR_PS5250),y)
	SENSOR_MODEL := ps5250
else ifeq ($(BR2_SENSOR_PS5260),y)
	SENSOR_MODEL := ps5260
else ifeq ($(BR2_SENSOR_PS5268),y)
	SENSOR_MODEL := ps5268
else ifeq ($(BR2_SENSOR_PS5270),y)
	SENSOR_MODEL := ps5270
else ifeq ($(BR2_SENSOR_PS5520),y)
	SENSOR_MODEL := ps5520
else ifeq ($(BR2_SENSOR_SC1235),y)
	SENSOR_MODEL := sc1235
else ifeq ($(BR2_SENSOR_SC1346),y)
	SENSOR_MODEL := sc1346
else ifeq ($(BR2_SENSOR_SC1A4T),y)
	SENSOR_MODEL := sc1a4t
else ifeq ($(BR2_SENSOR_SC200AI),y)
	SENSOR_MODEL := sc200ai
else ifeq ($(BR2_SENSOR_SC201CS),y)
	SENSOR_MODEL := sc201cs
else ifeq ($(BR2_SENSOR_SC202CS),y)
	SENSOR_MODEL := sc202cs
else ifeq ($(BR2_SENSOR_SC2210),y)
	SENSOR_MODEL := sc2210
else ifeq ($(BR2_SENSOR_SC2232),y)
	SENSOR_MODEL := sc2232
else ifeq ($(BR2_SENSOR_SC2232H),y)
	SENSOR_MODEL := sc2232h
else ifeq ($(BR2_SENSOR_SC2235),y)
	SENSOR_MODEL := sc2235
else ifeq ($(BR2_SENSOR_SC2239),y)
	SENSOR_MODEL := sc2239
else ifeq ($(BR2_SENSOR_SC2239P),y)
	SENSOR_MODEL := sc2239p
else ifeq ($(BR2_SENSOR_SC223A),y)
	SENSOR_MODEL := sc223a
else ifeq ($(BR2_SENSOR_SC230AI),y)
	SENSOR_MODEL := sc230ai
else ifeq ($(BR2_SENSOR_SC2300),y)
	SENSOR_MODEL := sc2300
else ifeq ($(BR2_SENSOR_SC2310),y)
	SENSOR_MODEL := sc2310
else ifeq ($(BR2_SENSOR_SC2315E),y)
	SENSOR_MODEL := sc2315e
else ifeq ($(BR2_SENSOR_SC2332),y)
	SENSOR_MODEL := sc2332
else ifeq ($(BR2_SENSOR_SC2335),y)
	SENSOR_MODEL := sc2335
else ifeq ($(BR2_SENSOR_SC2336),y)
	SENSOR_MODEL := sc2336
else ifeq ($(BR2_SENSOR_SC2336P),y)
	SENSOR_MODEL := sc2336p
else ifeq ($(BR2_SENSOR_SC301IOT),y)
	SENSOR_MODEL := sc301IoT
else ifeq ($(BR2_SENSOR_SC3235),y)
	SENSOR_MODEL := sc3235
else ifeq ($(BR2_SENSOR_SC3335),y)
	SENSOR_MODEL := sc3335
else ifeq ($(BR2_SENSOR_SC3336),y)
	SENSOR_MODEL := sc3336
else ifeq ($(BR2_SENSOR_SC3338),y)
	SENSOR_MODEL := sc3338
else ifeq ($(BR2_SENSOR_SC401AI),y)
	SENSOR_MODEL := sc401ai
else ifeq ($(BR2_SENSOR_SC4236),y)
	SENSOR_MODEL := sc4236
else ifeq ($(BR2_SENSOR_SC4236H),y)
	SENSOR_MODEL := sc4236h
else ifeq ($(BR2_SENSOR_SC4238),y)
	SENSOR_MODEL := sc4238
else ifeq ($(BR2_SENSOR_SC4335),y)
	SENSOR_MODEL := sc4335
else ifeq ($(BR2_SENSOR_SC4336),y)
	SENSOR_MODEL := sc4336
else ifeq ($(BR2_SENSOR_SC4336P),y)
	SENSOR_MODEL := sc4336p
else ifeq ($(BR2_SENSOR_SC450AI),y)
	SENSOR_MODEL := sc450ai
else ifeq ($(BR2_SENSOR_SC500AI),y)
	SENSOR_MODEL := sc500ai
else ifeq ($(BR2_SENSOR_SC5235),y)
	SENSOR_MODEL := sc5235
else ifeq ($(BR2_SENSOR_SP1405),y)
	SENSOR_MODEL := sp1405
else ifeq ($(BR2_SENSOR_TP2850),y)
	SENSOR_MODEL := tp2850
endif

export SENSOR_MODEL

ifeq ($(BR2_SENSOR_1_DUMMY),y)
	SENSOR_MODEL_1 :=
else ifeq ($(BR2_SENSOR_1_GC1084S0),y)
	SENSOR_MODEL_1 := gc1084s0
else ifeq ($(BR2_SENSOR_1_GC2053S0),y)
	SENSOR_MODEL_1 := gc2053s0
else ifeq ($(BR2_SENSOR_1_GC2083S0),y)
	SENSOR_MODEL_1 := gc2083s0
else ifeq ($(BR2_SENSOR_1_JXF38PS0),y)
	SENSOR_MODEL_1 := jxf38ps0
else ifeq ($(BR2_SENSOR_1_JXH63PS0),y)
	SENSOR_MODEL_1 := jxh63ps0
else ifeq ($(BR2_SENSOR_1_OS02G10S0),y)
	SENSOR_MODEL_1 := os02g10s0
else ifeq ($(BR2_SENSOR_1_SC1346S0),y)
	SENSOR_MODEL_1 := sc1346s0
else ifeq ($(BR2_SENSOR_1_SC1A4TS0),y)
	SENSOR_MODEL_1 := sc1a4ts0
else ifeq ($(BR2_SENSOR_1_SC2336S0),y)
	SENSOR_MODEL_1 := sc2336s0
else ifeq ($(BR2_SENSOR_1_SC2336PS0),y)
	SENSOR_MODEL_1 := sc2336ps0
endif

export SENSOR_MODEL_1

ifeq ($(BR2_SENSOR_2_DUMMY),y)
	SENSOR_MODEL_2 :=
else ifeq ($(BR2_SENSOR_2_GC1084S1),y)
	SENSOR_MODEL_2 := gc1084s1
else ifeq ($(BR2_SENSOR_2_GC2053S1),y)
	SENSOR_MODEL_2 := gc2053s1
else ifeq ($(BR2_SENSOR_2_GC2083S1),y)
	SENSOR_MODEL_2 := gc2083s1
else ifeq ($(BR2_SENSOR_2_JXF38PS1),y)
	SENSOR_MODEL_2 := jxf38ps1
else ifeq ($(BR2_SENSOR_2_JXH63PS1),y)
	SENSOR_MODEL_2 := jxh63ps1
else ifeq ($(BR2_SENSOR_2_OS02G10S1),y)
	SENSOR_MODEL_2 := os02g10s1
else ifeq ($(BR2_SENSOR_2_SC1346S1),y)
	SENSOR_MODEL_2 := sc1346s1
else ifeq ($(BR2_SENSOR_2_SC1A4TS1),y)
	SENSOR_MODEL_2 := sc1a4ts1
else ifeq ($(BR2_SENSOR_2_SC2336S1),y)
	SENSOR_MODEL_2 := sc2336s1
else ifeq ($(BR2_SENSOR_2_SC2336PS1),y)
	SENSOR_MODEL_2 := sc2336ps1
endif

export SENSOR_MODEL_2

#
# ISP
#

# ISP kernel reserved memory allocations
FOUND_RMEM := $(subst BR2_THINGINO_RMEM_,,$(strip \
	$(foreach v,$(filter BR2_THINGINO_RMEM_%,$(filter-out BR2_THINGINO_RMEM_CHOICE,$(.VARIABLES))), \
		$(if $(filter y,$($(v))),$(v)) \
	)))

# Set the default RMEM size based on SOC ram size if no explicit value found
# These values match the default values found in uboot by the soc ram size
# Default values should match what's in Config.soc.in since we can't use the BR2 variables directly
ifeq ($(FOUND_RMEM),)
	ifeq ($(SOC_RAM),64)
		ISP_RMEM := 23
	else ifeq ($(SOC_RAM),128)
		ISP_RMEM := 29
	else ifeq ($(SOC_RAM),256)
		ISP_RMEM := 64
	else
		ISP_RMEM := 32
	endif
else
	ISP_RMEM := $(FOUND_RMEM)
endif

export ISP_RMEM

FOUND_ISPMEM := $(subst BR2_THINGINO_ISPMEM_,,$(strip \
	$(foreach v,$(filter BR2_THINGINO_ISPMEM_%,$(filter-out BR2_THINGINO_ISPMEM_CHOICE,$(.VARIABLES))), \
		$(if $(filter y,$($(v))),$(v)) \
	)))

ifeq ($(FOUND_ISPMEM),)
	ISP_ISPMEM := 8
else
	ISP_ISPMEM := $(FOUND_ISPMEM)
endif

export ISP_ISPMEM

FOUND_NMEM := $(subst BR2_THINGINO_NMEM_,,$(strip \
	$(foreach v,$(filter BR2_THINGINO_NMEM_%,$(filter-out BR2_THINGINO_NMEM_CHOICE,$(.VARIABLES))), \
		$(if $(filter y,$($(v))),$(v)) \
	)))

ifeq ($(FOUND_NMEM),)
	ifeq ($(SOC_RAM),64)
		ISP_NMEM := 23
	else ifeq ($(SOC_RAM),128)
		ISP_NMEM := 29
	else ifeq ($(SOC_RAM),256)
		ISP_NMEM := 64
	else
		ISP_NMEM := 16
	endif
else
	ISP_NMEM := $(FOUND_NMEM)
endif

export ISP_NMEM

# Default IPU clock speed
ifeq ($(BR2_IPU_CLK_400MHZ),y)
	IPU_CLK := 400000000
else ifeq ($(BR2_IPU_CLK_450MHZ),y)
	IPU_CLK := 450000000
else ifeq ($(BR2_IPU_CLK_500MHZ),y)
	IPU_CLK := 500000000
else ifeq ($(BR2_IPU_CLK_550MHZ),y)
	IPU_CLK := 550000000
else ifeq ($(BR2_IPU_CLK_600MHZ),y)
	IPU_CLK := 600000000
else ifeq ($(BR2_IPU_CLK_650MHZ),y)
	IPU_CLK := 650000000
else
	IPU_CLK := 400000000
endif


# Default ISP clock speed
ifeq ($(BR2_ISP_CLK_90MHZ),y)
	ISP_CLK := 90000000
else ifeq ($(BR2_ISP_CLK_100MHZ),y)
	ISP_CLK := 100000000
else ifeq ($(BR2_ISP_CLK_120MHZ),y)
	ISP_CLK := 120000000
else ifeq ($(BR2_ISP_CLK_125MHZ),y)
	ISP_CLK := 125000000
else ifeq ($(BR2_ISP_CLK_150MHZ),y)
	ISP_CLK := 150000000
else ifeq ($(BR2_ISP_CLK_175MHZ),y)
	ISP_CLK := 175000000
else ifeq ($(BR2_ISP_CLK_200MHZ),y)
	ISP_CLK := 200000000
else ifeq ($(BR2_ISP_CLK_220MHZ),y)
	ISP_CLK := 220000000
else ifeq ($(BR2_ISP_CLK_225MHZ),y)
	ISP_CLK := 225000000
else ifeq ($(BR2_ISP_CLK_250MHZ),y)
	ISP_CLK := 250000000
else ifeq ($(BR2_ISP_CLK_300MHZ),y)
	ISP_CLK := 300000000
else ifeq ($(BR2_ISP_CLK_350MHZ),y)
	ISP_CLK := 350000000
else
	ISP_CLK := 100000000
endif

ifeq ($(BR2_AVPU_CLK_400MHZ),y)
	AVPU_CLK := 400000000
else ifeq ($(BR2_AVPU_CLK_450MHZ),y)
	AVPU_CLK := 450000000
else ifeq ($(BR2_AVPU_CLK_500MHZ),y)
	AVPU_CLK := 500000000
else ifeq ($(BR2_AVPU_CLK_550MHZ),y)
	AVPU_CLK := 550000000
else ifeq ($(BR2_AVPU_CLK_600MHZ),y)
	AVPU_CLK := 600000000
else ifeq ($(BR2_AVPU_CLK_650MHZ),y)
	AVPU_CLK := 650000000
else ifeq ($(BR2_AVPU_CLK_700MHZ),y)
	AVPU_CLK := 700000000
else
	AVPU_CLK := 400000000
endif

ifeq ($(BR2_AVPU_MPLL),y)
	AVPU_CLK_SRC := clk_name=mpll
else ifeq ($(BR2_AVPU_VPLL),y)
	AVPU_CLK_SRC := clk_name=vpll
else ifeq ($(BR2_AVPU_INTERNAL),y)
	AVPU_CLK_SRC :=
else
	AVPU_CLK_SRC :=
endif

ifeq ($(BR2_ISP_CLKA_400MHZ),y)
	ISP_CLKA_CLK := 400000000
else ifeq ($(BR2_ISP_CLKA_450MHZ),y)
	ISP_CLKA_CLK := 450000000
else ifeq ($(BR2_ISP_CLKA_500MHZ),y)
	ISP_CLKA_CLK := 500000000
else ifeq ($(BR2_ISP_CLKA_550MHZ),y)
	ISP_CLKA_CLK := 550000000
else ifeq ($(BR2_ISP_CLKA_600MHZ),y)
	ISP_CLKA_CLK := 600000000
else ifeq ($(BR2_ISP_CLKA_650MHZ),y)
	ISP_CLKA_CLK := 650000000
else ifeq ($(BR2_ISP_CLKA_700MHZ),y)
	ISP_CLKA_CLK := 700000000
else
	ISP_CLKA_CLK := 400000000
endif

ifeq ($(BR2_ISP_CLK_SCLKA),y)
	ISP_CLK_SRC := clk_name=sclka
else
	ISP_CLK_SRC :=
endif

ifeq ($(BR2_ISP_CLKA_SCLKA),y)
	ISP_CLKA_CLK_SRC := clka_name=sclka
else
	ISP_CLKA_CLK_SRC :=
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
	ISP_MEMOPT :=
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

export AVPU_CLK
export AVPU_CLK_SRC
export IPU_CLK
export ISP_CLK
export ISP_CLK_SRC
export ISP_CLKA_CLK
export ISP_CLKA_SRC
export ISP_MEMOPT
export ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM
export ISP_CH0_PRE_DEQUEUE_TIME
export ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS
export ISP_CH0_PRE_DEQUEUE_VALID_LINES

#
# FLASH CHIP
#

ifeq ($(FLASH_SIZE_8),y)
	FLASH_SIZE := $(SIZE_8M)
else ifeq ($(FLASH_SIZE_16),y)
	FLASH_SIZE := $(SIZE_16M)
else ifeq ($(FLASH_SIZE_32),y)
	FLASH_SIZE := $(SIZE_32M)
else ifeq ($(FLASH_SIZE_128),y)
	FLASH_SIZE := $(SIZE_128M)
else ifeq ($(FLASH_SIZE_256),y)
	FLASH_SIZE := $(SIZE_256M)
else ifeq ($(FLASH_SIZE_512),y)
	FLASH_SIZE := $(SIZE_512M)
else ifeq ($(FLASH_SIZE_1G),y)
	FLASH_SIZE := $(SIZE_1G)
else
	FLASH_SIZE := $(SIZE_8M)
endif

export FLASH_SIZE

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
