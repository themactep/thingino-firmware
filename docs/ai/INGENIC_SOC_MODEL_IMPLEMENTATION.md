# INGENIC_SOC_MODEL Implementation Summary

> **Partially implemented.** The `BR2_INGENIC_SOC_MODEL` string is live in
> `Config.soc.in`. The `get_soc_params.sh` / `soc_database.txt` lookup
> described in the sibling proposals was never committed: `thingino.mk`
> resolves the model through `soc/<vendor>/*.mk`. This note is historical
> and kept for context.

## What Was Done

`BR2_INGENIC_SOC_MODEL` replaces the per-SoC Kconfig booleans with a single
case-insensitive model string.

## Config.soc.in

Before: 100+ individual boolean entries.

After: one string input, `config BR2_INGENIC_SOC_MODEL`, with the supported
models listed in its help text.

## thingino.mk

The model is looked up through one makefile per SoC family:

```make
SOC_MODEL_INPUT := $(call qstrip,$(BR2_INGENIC_SOC_MODEL))
ifneq ($(SOC_MODEL_INPUT),)
	SOC_MODEL := $(shell echo $(SOC_MODEL_INPUT) | tr A-Z a-z)
	include $(wildcard $(BR2_EXTERNAL)/soc/$(SOC_VENDOR)/*.mk)
ifeq ($(SOC_FAMILY),)
$(error Unknown SoC model '$(SOC_MODEL)')
endif
endif
```

Each `soc/<vendor>/<family>.mk` filters on its own model names and sets
`SOC_FAMILY`, `SOC_ARCH`, `SOC_RAM_MB`, and `SOC_UBOOT` / `SOC_UBOOT_BIN`.

## Usage

```
BR2_INGENIC_SOC_MODEL="t31x"
```

The string is case-insensitive. Configurations that still carry the removed
`BR2_SOC_INGENIC_*` booleans set no model; convert them to the model string.

## Database proposal

The `scripts/soc_database.txt`, `scripts/get_soc_params.sh`, and
`scripts/validate_soc_database.sh` files described in
`README_SOC_DATABASE.md`, `SOC_DATABASE_SUMMARY.md`, and
`IMPLEMENTATION_GUIDE.md` were never committed. The per-family makefiles
under `soc/` are the source of truth.

## Testing

Every build exercises the lookup: `thingino.mk` stops with an error when no
`soc/<vendor>/*.mk` claims a non-empty model.

## Status

The model string is live. The proposed database lookup was replaced by the
`soc/` makefiles; treat the database snippets and commands in the sibling
documents as historical.
