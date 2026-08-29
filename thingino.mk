# Define qstrip if not already defined (usually defined by Buildroot)
qstrip ?= $(strip $(subst ",,$(1)))

#
# SOC
#

# The else branch is a fallback, not just the Kconfig default: this file is
# parsed before .config exists on some paths, and every existing defconfig sets
# no vendor symbol at all.
ifeq ($(BR2_SOC_VENDOR_SIGMASTAR),y)
SOC_VENDOR := sigmastar
else
SOC_VENDOR := ingenic
endif

# Target architecture of the cross toolchain, one line per vendor. It has to be
# resolved here rather than read from the BR2_mipsel/BR2_arm the SoC fragment
# already sets: fragments are appended to .config and never included as
# makefiles, so that symbol is not readable when SED_CONFIG_VARS runs.
ifeq ($(SOC_VENDOR),sigmastar)
SOC_TARGET_ARCH := arm
else
SOC_TARGET_ARCH := mipsel
endif

# The SoC model, from whichever vendor's symbol carries it. Kconfig keeps them
# mutually exclusive -- each depends on its vendor and the vendor is a choice --
# so at most one is ever set and the order below is not a precedence. Testing
# after qstrip rather than before is what makes an empty BR2_..._SOC_MODEL=""
# fall through, since "" is two characters to make and not an empty string.
SOC_MODEL_INPUT := $(call qstrip,$(BR2_INGENIC_SOC_MODEL))
ifeq ($(SOC_MODEL_INPUT),)
SOC_MODEL_INPUT := $(call qstrip,$(BR2_SIGMASTAR_SOC_MODEL))
endif
ifneq ($(SOC_MODEL_INPUT),)
	SOC_MODEL := $(shell echo $(SOC_MODEL_INPUT) | tr A-Z a-z)

	# One file per SoC family under soc/<vendor>/. Each sets SOC_FAMILY,
	# SOC_ARCH, SOC_RAM_MB and, where the vendor uses BR2_TARGET_UBOOT,
	# SOC_UBOOT / SOC_UBOOT_BIN. SOC_UBOOT is the U-Boot board/defconfig
	# name, already resolved for the flash type. Anything a SoC does not
	# have, it does not set -- consumers below use $(or ...) for the fallback.
	#
	# All of them are included and each opens with a $(filter) on its own
	# models, so only one file's body applies. The family cannot pick the
	# filename, because the family is one of the things being looked up.
	include $(wildcard $(BR2_EXTERNAL)/soc/$(SOC_VENDOR)/*.mk)

# A model no family claims leaves SOC_FAMILY empty, which is worth stopping for:
# the old lookup fell back to "unknown"/64 and built something wrong. Unindented
# because a tab-led $(error ...) is not a directive -- make reads it as a recipe
# and fails with "recipe commences before first target" instead.
ifeq ($(SOC_FAMILY),)
$(error Unknown $(SOC_VENDOR) SoC model '$(SOC_MODEL)': no soc/$(SOC_VENDOR)/*.mk claims it)
endif
endif

SOC_FAMILY_CAPS := $(shell echo $(SOC_FAMILY) | tr a-z A-Z)
SOC_MODEL_LESS_Z := $(subst z,,$(SOC_MODEL))

export SOC_VENDOR
export SOC_FAMILY
export SOC_FAMILY_CAPS
export SOC_MODEL
export SOC_MODEL_LESS_Z

# Per-device custom device tree: a single .dts in the camera profile dir
# replaces the SoC family's stock kernel tree. The thingino-kopt linux
# extension copies it over the family's kernel dts name before every
# kernel build (BR2_LINUX_KERNEL_CUSTOM_DTS_DIR is unusable here: it
# hides behind BR2_LINUX_KERNEL_DTS_SUPPORT, which uImage kernels that
# build their own dtb never enable).
CAMERA_DTS_FILE = $(wildcard $(BR2_EXTERNAL)/$(CAMERA_SUBDIR)/$(CAMERA)/*.dts)
ifeq ($(SOC_FAMILY),t40)
CAMERA_DTS_DEST = shark
else ifeq ($(SOC_FAMILY),t41)
CAMERA_DTS_DEST = marmot
else ifeq ($(SOC_FAMILY),t32)
CAMERA_DTS_DEST = goat
else ifeq ($(SOC_FAMILY),a1)
CAMERA_DTS_DEST = tucana
endif
ifneq ($(CAMERA_DTS_FILE),)
ifneq ($(words $(CAMERA_DTS_FILE)),1)
$(error Camera profile $(CAMERA) has more than one .dts file: $(CAMERA_DTS_FILE))
endif
ifeq ($(CAMERA_DTS_DEST),)
$(error Camera profile $(CAMERA) ships a .dts but SoC family '$(SOC_FAMILY)' has no known kernel dts name)
endif
endif
export CAMERA_DTS_FILE
export CAMERA_DTS_DEST
export SOC_RAM_MB
export SOC_ARCH
export SOC_TARGET_ARCH

#
# KERNEL
#

# default to older kernel if none set
ifeq ($(KERNEL_VERSION),)
	ifeq ($(KERNEL_VERSION_7),y)
		KERNEL_VERSION := 7.1-rc1
	else ifeq ($(KERNEL_VERSION_4),y)
		KERNEL_VERSION := 4.4.94
	else ifeq ($(SOC_FAMILY),t41)
		KERNEL_VERSION := 4.4.94
	else ifeq ($(SOC_FAMILY),t40)
		KERNEL_VERSION := 4.4.94
	else ifeq ($(SOC_FAMILY),a1)
		KERNEL_VERSION := 4.4.94
	else
		KERNEL_VERSION := 3.10.14
	endif
endif

KERNEL_SITE := https://github.com/gtxaspec/thingino-linux

ifeq ($(KERNEL_VERSION),7.1-rc1)
	KERNEL_BRANCH := ingenic-7.1-rc1
else ifeq ($(SOC_FAMILY),a1)
	KERNEL_BRANCH := ingenic-a1
else ifeq ($(SOC_FAMILY),c100)
	ifeq ($(KERNEL_VERSION),4.4.94)
		KERNEL_BRANCH := ingenic-t31-4.4.94
	else
		KERNEL_BRANCH := ingenic-t31
	endif
else ifeq ($(SOC_FAMILY),t41)
	ifeq ($(KERNEL_VERSION),4.4.94)
		KERNEL_BRANCH := ingenic-t41-4.4.94
	else
		KERNEL_BRANCH := ingenic-t41-3.10.14
	endif
else ifeq ($(SOC_FAMILY),t40)
	KERNEL_BRANCH := ingenic-t40
else ifeq ($(SOC_FAMILY),t31)
	ifeq ($(KERNEL_VERSION),4.4.94)
		KERNEL_BRANCH := ingenic-t31-4.4.94
	else
		KERNEL_BRANCH := ingenic-t31
	endif
else ifeq ($(SOC_FAMILY),t32)
	ifeq ($(KERNEL_VERSION),4.4.94)
		KERNEL_BRANCH := ingenic-t32-4.4.94
	else
		KERNEL_BRANCH := ingenic-t32
	endif
else ifeq ($(SOC_FAMILY),t23)
	ifeq ($(KERNEL_VERSION),4.4.94)
		KERNEL_BRANCH := ingenic-t23-4.4.94
		KERNEL_HASH := b8a1f1ed22272b844fd423871f4aca16e8b779ff
	else
		KERNEL_BRANCH := ingenic-t31
	endif
else
	KERNEL_BRANCH := ingenic-t31
endif

ifeq ($(KERNEL_HASH),)
	KERNEL_HASH := $(shell git ls-remote $(KERNEL_SITE) $(KERNEL_BRANCH) | head -1 | cut -f1)
endif
KERNEL_TARBALL_URL := $(KERNEL_SITE)/archive/$(KERNEL_HASH).tar.gz

ifeq ($(KERNEL_VERSION),7.1-rc1)
KERNEL_VERSION_7 := y
else
KERNEL_VERSION_7 := n
endif

ifeq ($(KERNEL_VERSION),4.4.94)
KERNEL_VERSION_4 := y
else
KERNEL_VERSION_4 := n
endif

export KERNEL_BRANCH
export KERNEL_HASH
export KERNEL_SITE
export KERNEL_TARBALL_URL
export KERNEL_VERSION
export KERNEL_VERSION_4
export KERNEL_VERSION_7

#
# IMAGE SENSOR
#

SENSOR_1_MODEL := $(call qstrip,$(BR2_SENSOR_1_NAME))
SENSOR_2_MODEL := $(call qstrip,$(BR2_SENSOR_2_NAME))
SENSOR_3_MODEL := $(call qstrip,$(BR2_SENSOR_3_NAME))
SENSOR_4_MODEL := $(call qstrip,$(BR2_SENSOR_4_NAME))

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

export ISP_NMEM_MB

#
# ISP / IPU / AVPU clock & configuration helpers
#
# resolve_clock_src -- maps Kconfig BR2_<PREFIX>_<SRC>=y to output=value
#   $(1) = Kconfig prefix (e.g. ISP_CLK)
#   $(2) = output key      (e.g. clk_name)
#   $(3) = space-separated SRC:value pairs
resolve_clock_src = $(strip \
  $(foreach _p,$(3), \
    $(if $(filter y,$(BR2_$(1)_$(firstword $(subst :, ,$(_p))))), \
      $(2)=$(lastword $(subst :, ,$(_p))))))

# resolve_clock_freq -- maps Kconfig BR2_<PREFIX>_<N>MHZ=y to output=N_hz
#   $(1) = Kconfig prefix (e.g. ISP_CLK)
#   $(2) = output key      (e.g. isp_clk)
#   $(3) = space-separated MHZ:hz_value pairs
resolve_clock_freq = $(strip \
  $(foreach _p,$(3), \
    $(if $(filter y,$(BR2_$(1)_$(firstword $(subst :, ,$(_p)))MHZ)), \
      $(2)=$(lastword $(subst :, ,$(_p))))))

# resolve_choice -- maps Kconfig BR2_<PREFIX>_<N>=y to output=value
#   $(1) = Kconfig prefix (e.g. ISP_MEMOPT)
#   $(2) = output key      (e.g. isp_memopt)
#   $(3) = space-separated N:value pairs (empty value -> output is empty)
resolve_choice = $(strip \
  $(foreach _p,$(3), \
    $(if $(filter y,$(BR2_$(1)_$(firstword $(subst :, ,$(_p))))), \
      $(if $(lastword $(subst :, ,$(_p))),$(2)=$(lastword $(subst :, ,$(_p)))))))

# isp_param -- maps Kconfig BR2_<NAME>=y to output=VALUE
#   $(1) = Kconfig boolean name (e.g. ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM)
#   $(2) = output key (e.g. isp_day_night_switch_drop_frame_num)
isp_param = $(strip \
  $(if $(filter y,$(BR2_$(1))),$(2)=$(BR2_$(1)_VALUE)))

#
# Clock assignments (source + frequency)
#

# IPU
IPU_CLK_SRC := $(call resolve_clock_src,IPU_CLK,clk_name,\
  SCLKA:sclka VPLL:vpll MPLL:mpll INTERNAL:)
IPU_CLK := $(call resolve_clock_freq,IPU_CLK,ipu_clk,\
  400:400000000 450:450000000 500:500000000 550:550000000 \
  600:600000000 650:650000000)

# AVPU
AVPU_CLK_SRC := $(call resolve_clock_src,AVPU,clk_name,\
  APLL:apll MPLL:mpll SCLKA:sclka VPLL:vpll INTERNAL:)
AVPU_CLK := $(call resolve_clock_freq,AVPU_CLK,avpu_clk,\
  400:400000000 450:450000000 500:500000000 550:550000000 \
  600:600000000 650:650000000 700:700000000)

# ISP
ISP_CLK_SRC := $(call resolve_clock_src,ISP_CLK,clk_name,\
  SCLKA:sclka VPLL:vpll MPLL:mpll INTERNAL:)
ISP_CLK := $(call resolve_clock_freq,ISP_CLK,isp_clk,\
  90:90000000   100:100000000 120:120000000 125:125000000 \
  150:150000000 175:175000000 200:200000000 220:220000000 \
  225:225000000 250:250000000 300:300000000 350:350000000)

# ISP_CLKA
ISP_CLKA_CLK_SRC := $(call resolve_clock_src,ISP_CLKA,clka_name,\
  SCLKA:sclka INTERNAL:)
ISP_CLKA_CLK := $(call resolve_clock_freq,ISP_CLKA,isp_clka,\
  400:400000000 450:450000000 500:500000000 550:550000000 \
  600:600000000 650:650000000 700:700000000)

# ISP_CLKS
ISP_CLKS_CLK_SRC := $(call resolve_clock_src,ISP_CLKS,clks_name,\
  SCLKA:sclka VPLL:vpll MPLL:mpll INTERNAL:)
ISP_CLKS_CLK := $(call resolve_clock_freq,ISP_CLKS,isp_clks,\
  400:400000000 450:450000000 500:500000000 550:550000000 \
  600:600000000 650:650000000 700:700000000)

#
# ISP configuration parameters
#

# ISP_MEMOPT: choice with SOC_RAM_MB fallback
ISP_MEMOPT := $(call resolve_choice,ISP_MEMOPT,isp_memopt,\
  0: 1:1 2:2 3:3)
ifneq ($(ISP_MEMOPT),)
  # add trailing space so the later $(strip) doesn't collapse empty choice
endif
ifeq ($(ISP_MEMOPT),)
ifneq ($(SOC_RAM_MB),)
ifeq ($(shell test $(SOC_RAM_MB) -le 64 && ! echo "$(SOC_FAMILY)" | grep -Eq "t10|t20|t21|t30" && echo true),true)
	ISP_MEMOPT := isp_memopt=1
endif
endif
endif

ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM := $(call isp_param,ISP_DAY_NIGHT_SWITCH_DROP_FRAME_NUM,isp_day_night_switch_drop_frame_num)
ISP_CH0_PRE_DEQUEUE_TIME             := $(call isp_param,ISP_CH0_PRE_DEQUEUE_TIME,isp_ch0_pre_dequeue_time)
ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS := $(call isp_param,ISP_CH0_PRE_DEQUEUE_INTERRUPT_PROCESS,isp_ch0_pre_dequeue_interrupt_process)
ISP_CH0_PRE_DEQUEUE_VALID_LINES      := $(call isp_param,ISP_CH0_PRE_DEQUEUE_VALID_LINES,isp_ch0_pre_dequeue_valid_lines)
ISP_CH1_DEQUEUE_DELAY_TIME           := $(call isp_param,ISP_CH1_DEQUEUE_DELAY_TIME,isp_ch1_dequeue_delay_time)
ISP_MIPI_SWITCH_GPIO                 := $(call isp_param,ISP_MIPI_SWITCH_GPIO,mipi_switch_gpio)

ISP_DIRECT_MODE := $(call resolve_choice,ISP_DIRECT_MODE,direct_mode,\
  0:0 1:1 2:2)
ifeq ($(ISP_DIRECT_MODE),)
	ISP_DIRECT_MODE := direct_mode=0
endif

ISP_IVDC_MEM_LINE       := $(call isp_param,ISP_IVDC_MEM_LINE,ivdc_mem_line)
ISP_IVDC_THRESHOLD_LINE := $(call isp_param,ISP_IVDC_THRESHOLD_LINE,ivdc_threshold_line)
ISP_CONFIG_HZ           := $(call isp_param,ISP_CONFIG_HZ,isp_config_hz)

ISP_PRINT_LEVEL := $(call resolve_choice,ISP_PRINT_LEVEL,print_level,\
  0:0 1:1 2:2 3:3)
ifeq ($(ISP_PRINT_LEVEL),)
	ifeq ($(shell echo "$(SOC_FAMILY)" | grep -Eq "t10|t20|t21" && echo true),true)
		ISP_PRINT_LEVEL :=
	else
		ISP_PRINT_LEVEL := print_level=1
	endif
endif

ISP_ISPW        := $(call isp_param,ISP_ISPW,ispw)
ISP_ISPH        := $(call isp_param,ISP_ISPH,isph)
ISP_ISPTOP      := $(call isp_param,ISP_ISPTOP,isptop)
ISP_ISPLEFT     := $(call isp_param,ISP_ISPLEFT,ispleft)
ISP_ISPCROP     := $(call isp_param,ISP_ISPCROP,ispcrop)
ISP_ISPCROPWH   := $(call isp_param,ISP_ISPCROPWH,ispcropwh)
ISP_ISPCROPTL   := $(call isp_param,ISP_ISPCROPTL,ispcroptl)
ISP_ISPSCALER   := $(call isp_param,ISP_ISPSCALER,isp_scaler)
ISP_ISPSCALERWH := $(call isp_param,ISP_ISPSCALERWH,isp_scalerwh)
ISP_ISP_M1_BUFS := $(call isp_param,ISP_ISP_M1_BUFS,isp_m1_bufs)
ISP_ISP_M2_BUFS := $(call isp_param,ISP_ISP_M2_BUFS,isp_m2_bufs)


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

ifeq ($(BR2_TARGET_UBOOT_BOARDNAME),)
	# SOC_UBOOT is resolved for the flash type by the soc/<vendor>/ file.
	UBOOT_BOARDNAME := $(or $(SOC_UBOOT),unknown)
	BR2_TARGET_UBOOT_BOARDNAME := $(UBOOT_BOARDNAME)
else
	# The camera defconfig named a board. Carry it into UBOOT_BOARDNAME too:
	# Makefile.targets writes UBOOT_BOARDNAME back out to the generated
	# .config, so leaving it unset here clobbers the camera's own value with
	# an empty string.
	UBOOT_BOARDNAME := $(patsubst "%",%,$(BR2_TARGET_UBOOT_BOARDNAME))
	UBOOT_BOARDNAME_FROM_CAMERA := y
endif

# Flash type used for U-Boot defconfig lookup
ifeq ($(BR2_THINGINO_FLASH_NAND),y)
UBOOT_BOARD_FLASH := nand
else
UBOOT_BOARD_FLASH := nor
endif

# Kconfig choice suffix for the kernel SFC NAND mtd-id: the mtdparts= mtd-id in
# the generated bootargs must match the kernel driver's mtd name, which differs
# per SoC kernel tree ("sfc_nand" on the t40 4.4 tree, "sfc0_nand" on t41).
# Substituted into flash-nand.fragment by SED_CONFIG_VARS.
ifeq ($(SOC_FAMILY),t41)
NAND_FLASH_CONTROLLER_SYM := SFC0_NAND
NAND_FLASH_CONTROLLER := sfc0_nand
else
NAND_FLASH_CONTROLLER_SYM := SFC_NAND
NAND_FLASH_CONTROLLER := sfc_nand
endif
export NAND_FLASH_CONTROLLER_SYM

ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_JZ_SFC),y)
	UBOOT_FLASH_CONTROLLER := jz_sfc
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC_NAND),y)
	UBOOT_FLASH_CONTROLLER := sfc_nand
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC0_NOR),y)
	UBOOT_FLASH_CONTROLLER := sfc0_nor
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC1_NOR),y)
	UBOOT_FLASH_CONTROLLER := sfc1_nor
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC0_NAND),y)
	UBOOT_FLASH_CONTROLLER := sfc0_nand
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_SFC1_NAND),y)
	UBOOT_FLASH_CONTROLLER := sfc1_nand
else ifeq ($(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_CUSTOM),y)
	UBOOT_FLASH_CONTROLLER := $(patsubst "%",%,$(BR2_PACKAGE_THINGINO_UBOOT_FLASH_CONTROLLER_CUSTOM_STRING))
else ifeq ($(BR2_THINGINO_FLASH_NAND),y)
	# The top-level make only includes the camera defconfig (board.mk), not the
	# fragments, so the FLASH_CONTROLLER choice set by flash-nand.fragment is
	# invisible here unless the camera defconfig sets it. Fall back to the same
	# per-SoC NAND mtd-id the fragment resolves to.
	UBOOT_FLASH_CONTROLLER := $(NAND_FLASH_CONTROLLER)
else
	UBOOT_FLASH_CONTROLLER := jz_sfc
endif
export UBOOT_FLASH_CONTROLLER

ifeq ($(BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME),)
	BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME := "$(or $(SOC_UBOOT_BIN),u-boot-with-spl-lzma.bin)"
endif

# Whether a camera-named board is worth checking against the U-Boot being
# built, and whether that U-Boot has it.
#
# The list comes from package/all-patches/uboot/<version>/, which CI
# regenerates from the pinned ingenic-t-series tree, so it holds the same
# configs/ that tree does. Only meaningful for the Kconfig-era trees: 2013.07
# picks boards out of boards.cfg and ignores BR2_TARGET_UBOOT_BOARD_DEFCONFIG
# entirely, and a custom fork cannot be enumerated from here at all -- in both
# cases there is nothing to check and the camera's name is taken as given.
UBOOT_PATCH_FILES := $(wildcard $(BR2_EXTERNAL)/package/all-patches/uboot/$(subst -,.,$(THINGINO_UBOOT_VERSION_TAG))/*.patch)
UBOOT_BOARDNAME_CHECKABLE := $(if $(filter y,$(UBOOT_BOARDNAME_FROM_CAMERA)),$(if $(filter-out 2013-07,$(THINGINO_UBOOT_VERSION_TAG)),$(if $(UBOOT_PATCH_FILES),y)))
UBOOT_BOARDNAME_MISSING := $(if $(filter y,$(UBOOT_BOARDNAME_CHECKABLE)),$(if $(shell grep -lsF 'diff --git a/configs/$(UBOOT_BOARDNAME)_defconfig ' $(UBOOT_PATCH_FILES)),,y))

ifeq ($(BR2_TARGET_UBOOT_BOARD_DEFCONFIG),)
	# BR2_TARGET_UBOOT_BOARDNAME only selects <name>_config on U-Boot's legacy
	# build system. The Kconfig build system 2026.07 uses takes
	# <name>_defconfig from BR2_TARGET_UBOOT_BOARD_DEFCONFIG instead, so a
	# camera that names a board has to reach that symbol -- otherwise its board
	# choice is dropped for the plain SoC defconfig with nothing to show for it
	# (which is how the mmc1bit boards ended up running a 4-bit SD devicetree).
	# UBOOT_BOARDNAME is already resolved above (camera name, else SOC_UBOOT).
	UBOOT_DEFCONFIG := $(UBOOT_BOARDNAME)
ifeq ($(UBOOT_BOARDNAME_MISSING),y)
	# Some camera defconfigs still name 2013.07-era boards that the 2026.07
	# tree never picked up (msc1, xiaomi, uart0, motorcomm). Those fall back to
	# the SoC default the same as before -- but say so, rather than either
	# failing the U-Boot configure or going quiet about it again.
	# Unindented $(warning) for the same reason as the SOC_FAMILY $(error).
$(warning U-Boot $(THINGINO_UBOOT_VERSION_TAG) has no $(UBOOT_BOARDNAME)_defconfig, falling back to $(or $(SOC_UBOOT),unknown))
	UBOOT_DEFCONFIG := $(or $(SOC_UBOOT),unknown)
endif
	BR2_TARGET_UBOOT_BOARD_DEFCONFIG := $(UBOOT_DEFCONFIG)
else
	UBOOT_DEFCONFIG := $(patsubst "%",%,$(BR2_TARGET_UBOOT_BOARD_DEFCONFIG))
endif

ifeq ($(SOC_MODEL),t10l)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t10l.config
else ifeq ($(SOC_MODEL),t20l)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t20l.config
else ifeq ($(SOC_MODEL),t20x)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t20x.config
else ifeq ($(SOC_MODEL),t23dl)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t23dl.config
else ifeq ($(SOC_MODEL),t30x)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t30x.config
else ifeq ($(SOC_MODEL),t31a)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t31a.config
else ifeq ($(SOC_MODEL),t31al)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t31al.config
else ifeq ($(SOC_MODEL),t31l)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t31l.config
else ifeq ($(SOC_MODEL),t31lc)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t31lc.config
else ifneq ($(filter t31x t31zx,$(SOC_MODEL)),)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t31x.config
else ifeq ($(SOC_MODEL),c100)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/c100.config
else ifeq ($(SOC_MODEL),t32nq)
	UBOOT_VARIANT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/variants/t32nq.config
endif

# NAND keeps the U-Boot env in a UBI volume, NOT a raw flash offset, so it needs
# a different layout fragment than NOR. Applying the NOR fragment to a NAND build
# would wrongly point the env at a raw offset.
ifeq ($(BR2_THINGINO_FLASH_NAND),y)
UBOOT_LAYOUT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/layout/sfcnand.config
else
UBOOT_LAYOUT_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/layout/sfcnor.config
endif

UBOOT_CONFIG_FRAGMENT_FILES :=
ifneq ($(wildcard $(UBOOT_LAYOUT_FRAGMENT)),)
	UBOOT_CONFIG_FRAGMENT_FILES += $(UBOOT_LAYOUT_FRAGMENT)
endif

ifneq ($(wildcard $(UBOOT_VARIANT_FRAGMENT)),)
	UBOOT_CONFIG_FRAGMENT_FILES += $(UBOOT_VARIANT_FRAGMENT)
endif

UBOOT_BOARD_FRAGMENT := $(BR2_EXTERNAL)/configs/uboot/boards/$(patsubst "%",%,$(BR2_TARGET_UBOOT_BOARDNAME)).config
ifneq ($(wildcard $(UBOOT_BOARD_FRAGMENT)),)
	UBOOT_CONFIG_FRAGMENT_FILES += $(UBOOT_BOARD_FRAGMENT)
endif

ifeq ($(BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES),)
	BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES := $(strip $(UBOOT_CONFIG_FRAGMENT_FILES))
endif

export UBOOT_BOARDNAME
export UBOOT_DEFCONFIG
export UBOOT_VARIANT_FRAGMENT
export UBOOT_CONFIG_FRAGMENT_FILES
export BR2_TARGET_UBOOT_BOARDNAME
export BR2_TARGET_UBOOT_BOARD_DEFCONFIG
export BR2_TARGET_UBOOT_CONFIG_FRAGMENT_FILES
export BR2_TARGET_UBOOT_FORMAT_CUSTOM_NAME

#
# STREAMER
#

ifeq ($(BR2_PACKAGE_RAPTOR_IPC),y)
	STREAMER := raptor
else ifeq ($(BR2_PACKAGE_PRUDYNT_T),y)
	STREAMER := prudynt
else ifeq ($(BR2_PACKAGE_STRERO),y)
	STREAMER := strero
else ifeq ($(BR2_PACKAGE_TIMPS),y)
	STREAMER := timps
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
