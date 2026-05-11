# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Thingino is an open-source Linux firmware for Ingenic SoC IP cameras, built as a `BR2_EXTERNAL` tree on top of Buildroot. It does **not** replace Buildroot — it extends it with custom packages, board configs, and overlays. The `buildroot/` and `linux/` directories are git submodules.

Supported: 50+ camera models across SoC families T10, T20, T21, T23, T30, T31, T40, T41, A1, C100.

## Build Commands

All builds require selecting a target camera via `CAMERA=` or interactively.

```bash
# Initial setup (fetch submodules, check host prerequisites)
make update

# Full build for a specific camera
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make

# Fast incremental build (most common during development)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make fast

# Release build (distclean + full build)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make release

# Interactive config
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make menuconfig

# Save modified config back to the camera defconfig
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make saveconfig

# Edit a camera defconfig directly
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make edit-defconfig

# Rebuild a single package (combines dirclean + build)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make rebuild-<packagename>

# OTA update to a running camera
CAMERA=atom_cam2_t31x_gc2053_atbm6031 IP=192.168.1.42 make ota
```

There are no automated test targets. Build validation happens via GitHub Actions (`.github/workflows/`).

Output lands in `output/<branch>/<camera>-<kernel_version>/`.

## Architecture

```
configs/cameras/<camera_name>/   # Per-camera defconfigs
configs/fragments/               # Reusable config fragments (toolchain, kernel, rootfs, soc, etc.)
package/<name>/                  # Custom Buildroot packages (50+)
overlay/                         # Root filesystem overlay (applied to all builds)
board/ingenic/                   # Board-level files (DTBs, patches)
linux/                           # Linux kernel (submodule, branches per SoC)
buildroot/                       # Buildroot source (submodule)
scripts/                         # Helper scripts
thingino.mk                      # SOC/kernel/flash layout variable definitions
board.mk                         # Camera config loading and variable exports
external.mk                      # Auto-includes all package/*.mk files
```

## Camera Naming Convention

```
<brand>_<model>_<soc>_<sensor>_<wifi_chip>
```

Example: `atom_cam2_t31x_gc2053_atbm6031`
Defconfig: `configs/cameras/atom_cam2_t31x_gc2053_atbm6031/atom_cam2_t31x_gc2053_atbm6031_defconfig`

The first line of each defconfig is `# NAME: <human readable name>`; the second line is `# FRAG: <space-separated fragment names>`.

## Key Conventions

### SOC and Kernel Variables

`thingino.mk` maps `BR2_SOC_INGENIC_*` Kconfig symbols to runtime variables:
- `SOC_FAMILY` (e.g., `t31`), `SOC_MODEL` (e.g., `t31x`), `SOC_RAM_MB`
- `KERNEL_VERSION` — either `3.10` (XBurst1: T10/T20/T21/T30/T31) or `4.4` (XBurst2: T23/T40/T41/A1)
- `BR2_XBURST_1` / `BR2_XBURST_2` — CPU architecture variant

Gate kernel-version-specific code in package makefiles:
```makefile
ifeq ($(KERNEL_VERSION),3.10)
    PKG_CFLAGS += -DCONFIG_KERNEL_3_10
endif
```

### Adding or Modifying a Package

Each package in `package/<name>/` requires:
- `<name>.mk` — Buildroot package makefile (defines `<NAME>_VERSION`, `<NAME>_SITE`, install commands)
- `Config.in` — Kconfig menu entry
- Must be referenced from `package/Config.in` or a parent `Config.in` to appear in menuconfig

`external.mk` auto-includes all `package/*/*.mk` files.

### Overlay Files

Files under `overlay/` are merged into the target root filesystem, mirroring the target path:
- `overlay/etc/init.d/` → `/etc/init.d/` — init scripts use `SXXname` naming (XX = start order)

### Config Fragments

Fragments in `configs/fragments/` are reusable Buildroot config snippets. A defconfig's `# FRAG:` header line lists which fragments to merge during `make defconfig`.

### Local Development Overrides

- `overrides/<package>/` — local package source used as-is (patches from `package/<name>/patches/` are **not** applied)
- `local.mk` — local variable/package overrides (not committed)

Override workflow:
1. Clone/extract package source to `overrides/<package>/`
2. Apply all existing package patches manually
3. Create a git repo and commit the base state
4. Make and test changes
5. Create a patch with `git diff` and add to `package/<name>/patches/`
6. Rebuild: `CAMERA=<cam> make rebuild-<packagename>`

### SSH / SCP

Thingino uses dropbear. File transfers require: `scp -O` (capital O flag).

### Dependency Check

`scripts/dep_check.sh` validates host tools on first `make`. Skipped when `WORKFLOW=1` (CI) or `.prereqs.done` exists. Repo path must not contain spaces.

## Work Ethics

- Do not lie, assume, or hallucinate. Follow facts; ask the user if facts are missing.
- Do not write documentation unless explicitly asked.
- Always test changes. Write tests when solving issues. Do not commit until all tests pass.
