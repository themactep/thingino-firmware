# Example refactored SOC section for thingino.mk
# This shows how to replace the 390-line ifeq chain with database lookups
# 
# BEFORE: ~390 lines of repetitive ifeq statements
# AFTER:  ~50 lines using database lookups

$(info --- FILE: thingino.mk)

#
# SOC
#

SOC_VENDOR := ingenic

# Special handling for DUMMY SoC (testing/development)
ifeq ($(BR2_SOC_INGENIC_DUMMY),y)
	SOC_FAMILY := t31
	SOC_MODEL := t31x
	SOC_RAM_MB := 128
	BR2_SOC_INGENIC_T31 := y
	BR2_XBURST_1 := y
	UBOOT_BOARDNAME := "isvp_t31_sfcnor_ddr128M"
else
	# Extract SoC model from BR2 config variables
	# Find which BR2_SOC_INGENIC_* variable is set to 'y'
	SOC_MODEL_RAW := $(foreach v,$(filter BR2_SOC_INGENIC_%,$(.VARIABLES)),$(if $(filter y,$($(v))),$(v)))
	SOC_MODEL := $(shell echo $(SOC_MODEL_RAW) | sed 's/BR2_SOC_INGENIC_//' | tr A-Z a-z)
	
	# Query database for SoC parameters
	SOC_FAMILY := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) family 2>/dev/null || echo "unknown")
	SOC_RAM_MB := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) ram 2>/dev/null || echo "64")
	XBURST_VER := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) arch 2>/dev/null || echo "1")
	
	# Set family-specific BR2 variable (e.g., BR2_SOC_INGENIC_T31)
	BR2_SOC_INGENIC_$(shell echo $(SOC_FAMILY) | tr a-z A-Z) := y
	
	# Set architecture variables based on xburst version
	ifeq ($(XBURST_VER),1)
		BR2_XBURST_1 := y
		SOC_ARCH := xburst1
	else ifeq ($(XBURST_VER),2)
		BR2_XBURST_2 := y
		SOC_ARCH := xburst2
	else
		# Fallback to xburst1 if unknown
		BR2_XBURST_1 := y
		SOC_ARCH := xburst1
	endif
	
	# Get U-Boot board name based on flash type
	ifeq ($(BR2_THINGINO_FLASH_NAND),y)
		UBOOT_BOARDNAME := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) uboot nand 2>/dev/null || echo "unknown")
	else
		UBOOT_BOARDNAME := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) uboot nor 2>/dev/null || echo "unknown")
	endif
	
	# Special case: C100 family detection
	# C100 uses different family depending on kernel version
	ifeq ($(SOC_MODEL),c100)
		ifeq ($(KERNEL_VERSION_4),y)
			SOC_FAMILY := c100
			BR2_SOC_INGENIC_C100 := y
		else
			SOC_FAMILY := t31
			BR2_SOC_INGENIC_T31 := y
		endif
	endif
endif

# Derived variables
SOC_FAMILY_CAPS := $(shell echo $(SOC_FAMILY) | tr a-z A-Z)
SOC_MODEL_LESS_Z := $(subst z,,$(SOC_MODEL))

# Export all variables for use in other makefiles and packages
export BR2_SOC_INGENIC_A1
export BR2_SOC_INGENIC_T10
export BR2_SOC_INGENIC_T20
export BR2_SOC_INGENIC_T21
export BR2_SOC_INGENIC_T23
export BR2_SOC_INGENIC_T30
export BR2_SOC_INGENIC_T31
export BR2_SOC_INGENIC_T40
export BR2_SOC_INGENIC_T41
export BR2_SOC_INGENIC_C100
export BR2_XBURST_1
export BR2_XBURST_2
export SOC_VENDOR
export SOC_FAMILY
export SOC_FAMILY_CAPS
export SOC_MODEL
export SOC_MODEL_LESS_Z
export SOC_RAM_MB
export SOC_ARCH

#
# NOTES:
# - This replaces 390 lines with ~70 lines
# - All SoC data now centralized in scripts/soc_database.txt
# - Adding new SoC: just add one line to database
# - Easier to maintain and less error-prone
# - Database serves as documentation
#
