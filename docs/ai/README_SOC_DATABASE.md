# SoC Database System

This directory contains a data-driven system for managing SoC parameters.

## Files

- **soc_database.txt** - Central database of all SoC models and their parameters
- **get_soc_params.sh** - Script to query the database

## Database Format

```
# Format: model,family,arch,ram_mb,uboot_board_nor,uboot_board_nand
# arch: 1=xburst1, 2=xburst2
# uboot_board_nand: use "-" if NAND not supported
```

## Script Usage

```bash
./scripts/get_soc_params.sh <soc_model> <param> [flash_type]
```

**Parameters:**
- `soc_model`: SoC model name (e.g., t31x, t40n) - case insensitive
- `param`: One of: `family`, `arch`, `ram`, `uboot`
- `flash_type`: (optional, only for uboot) `nand` or `nor` (default: nor)

**Examples:**

```bash
# Get SoC family
./scripts/get_soc_params.sh t31x family
# Output: t31

# Get architecture (1=xburst1, 2=xburst2)
./scripts/get_soc_params.sh t40n arch
# Output: 2

# Get RAM size in MB
./scripts/get_soc_params.sh t41a ram
# Output: 512

# Get U-Boot board name for NOR flash
./scripts/get_soc_params.sh t31x uboot nor
# Output: isvp_t31_sfcnor_ddr128M

# Get U-Boot board name for NAND flash
./scripts/get_soc_params.sh t31x uboot nand
# Output: isvp_t31_sfcnand_ddr128M
```

## Usage in Makefile

Replace the long ifeq chain in thingino.mk with:

```make
# Extract SoC model from BR2 config
SOC_MODEL_RAW := $(foreach v,$(filter BR2_SOC_INGENIC_%,$(.VARIABLES)),$(if $(filter y,$($(v))),$(v)))
SOC_MODEL := $(shell echo $(SOC_MODEL_RAW) | sed 's/BR2_SOC_INGENIC_//' | tr A-Z a-z)

# Query database for parameters
SOC_FAMILY := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) family)
SOC_RAM_MB := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) ram)
XBURST_VER := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) arch)

# Set architecture variables
ifeq ($(XBURST_VER),1)
    BR2_XBURST_1 := y
    SOC_ARCH := xburst1
else
    BR2_XBURST_2 := y
    SOC_ARCH := xburst2
endif

# Get U-Boot board name based on flash type
ifeq ($(BR2_THINGINO_FLASH_NAND),y)
    UBOOT_BOARDNAME := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) uboot nand)
else
    UBOOT_BOARDNAME := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) uboot nor)
endif
```

## Benefits

✅ **Single source of truth** - All SoC data in one file
✅ **Easy maintenance** - Add new SoCs by adding one line
✅ **Reduced errors** - No more copy-paste mistakes
✅ **Better readability** - Tabular data vs 390 lines of ifeq
✅ **Documentation** - Database serves as SoC reference
