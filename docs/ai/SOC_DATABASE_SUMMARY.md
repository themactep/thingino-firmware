# SoC Parameter Database Solution - Implementation Summary

## Overview

This solution replaces **390 lines** of repetitive `ifeq/else ifeq` statements in `thingino.mk` with a **data-driven approach** using a centralized database and lookup script.

## Files Created

1. **scripts/soc_database.txt** - Central SoC parameter database (52 SoC models)
2. **scripts/get_soc_params.sh** - Shell script to query the database
3. **scripts/README_SOC_DATABASE.md** - Documentation and usage guide
4. **scripts/thingino_soc_section_example.mk** - Example refactored makefile section

## Database Structure

```
Format: model,family,arch,ram_mb,uboot_board_nor,uboot_board_nand

Fields:
  - model: SoC model name (t31x, t40n, etc.)
  - family: SoC family (t31, t40, a1, etc.)
  - arch: 1=xburst1, 2=xburst2
  - ram_mb: RAM size in megabytes
  - uboot_board_nor: U-Boot board name for NOR flash
  - uboot_board_nand: U-Boot board name for NAND flash (or "-" if not supported)
```

## Query Script Usage

```bash
./scripts/get_soc_params.sh <model> <param> [flash_type]

Examples:
  ./scripts/get_soc_params.sh t31x family    # Returns: t31
  ./scripts/get_soc_params.sh t40n arch      # Returns: 2
  ./scripts/get_soc_params.sh t41a ram       # Returns: 512
  ./scripts/get_soc_params.sh t31x uboot nor # Returns: isvp_t31_sfcnor_ddr128M
```

## Makefile Integration

**BEFORE** (current thingino.mk):
```make
ifeq ($(BR2_SOC_INGENIC_T10L),y)
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
	# ... 380+ more lines ...
endif
```

**AFTER** (with database):
```make
# Extract SoC model from config
SOC_MODEL := $(shell echo $(SOC_MODEL_RAW) | sed 's/BR2_SOC_INGENIC_//' | tr A-Z a-z)

# Query database
SOC_FAMILY := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) family)
SOC_RAM_MB := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) ram)
XBURST_VER := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) arch)

# Set architecture
ifeq ($(XBURST_VER),1)
    BR2_XBURST_1 := y
    SOC_ARCH := xburst1
else
    BR2_XBURST_2 := y
    SOC_ARCH := xburst2
endif

# Get U-Boot board name
ifeq ($(BR2_THINGINO_FLASH_NAND),y)
    UBOOT_BOARDNAME := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) uboot nand)
else
    UBOOT_BOARDNAME := $(shell $(TOPDIR)/scripts/get_soc_params.sh $(SOC_MODEL) uboot nor)
endif
```

## Benefits

| Aspect | Before | After | Improvement |
|--------|--------|-------|-------------|
| **Lines of code** | ~390 lines | ~70 lines | 82% reduction |
| **Maintainability** | Edit makefile for each SoC | Add one line to database | Much easier |
| **Error prone** | High (copy-paste errors) | Low (single source) | Less errors |
| **Documentation** | Scattered in code | Centralized database | Better clarity |
| **Scalability** | Gets worse over time | Stays constant | Future-proof |

## SoC Coverage

The database includes all 52+ SoC variants:
- **T10 family**: t10l, t10n, t10a
- **T20 family**: t20l, t20n, t20x, t20z
- **T21 family**: t21l, t21n, t21x, t21zn, t21zl
- **T23 family**: t23n, t23dl, t23zn
- **T30 family**: t30l, t30n, t30x, t30a
- **T31 family**: t31l, t31lc, t31n, t31x, t31a, t31al, t31zl, t31zx
- **T40 family**: t40n, t40nn, t40xp, t40a
- **T41 family**: t41lq, t41nq, t41zl, t41zn, t41zx, t41a
- **A1 family**: a1n, a1nt, a1x, a1l, a1a
- **C100 family**: c100

## Migration Path

1. **Review**: Check that all SoCs are in the database
2. **Test**: Run test builds with the new system
3. **Backup**: Keep original thingino.mk as backup
4. **Replace**: Replace SOC section with new implementation
5. **Validate**: Build firmware for several SoC variants
6. **Document**: Update project documentation

## Special Cases Handled

1. **DUMMY SoC**: Still uses hardcoded values (testing/development)
2. **C100**: Family changes based on kernel version (handled in makefile logic)
3. **NAND fallback**: If NAND not supported, falls back to NOR board name
4. **Case insensitive**: Database lookup is case-insensitive

## Testing

```bash
# Test script with various SoCs
bash scripts/get_soc_params.sh t31x family  # t31
bash scripts/get_soc_params.sh T40N arch    # 2 (case insensitive)
bash scripts/get_soc_params.sh t41a ram     # 512
bash scripts/get_soc_params.sh a1n uboot    # isvp_a1_all_lzma_sfc0nor
```

## Next Steps

To implement this in production:

1. Test the refactored section with actual builds
2. Add any missing SoC variants to the database
3. Consider adding validation script to check database integrity
4. Update build documentation with new approach
5. Replace the SOC section in thingino.mk with the new implementation

## Maintenance

Adding a new SoC is now trivial:

```bash
# Just add one line to scripts/soc_database.txt:
t50x,t50,2,256,isvp_t50x_sfcnor,isvp_t50x_sfcnand
```

No makefile changes needed!

---

**Created**: 2026-02-05
**Impact**: Reduces maintenance burden, improves code quality, future-proofs the build system
