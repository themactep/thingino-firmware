# Thingino Firmware - Copilot Instructions

## Project Overview

Thingino is an open-source Linux firmware for Ingenic SoC IP cameras, built on top of [Buildroot](https://buildroot.org/). This repository is a `BR2_EXTERNAL` tree — it does **not** replace Buildroot but extends it with custom packages, board configs, and overlays. The `buildroot/` and `linux/` directories are git submodules.

## Build Commands

All builds require selecting a target camera. `CAMERA` can be passed on the command line or selected interactively.

```bash
# Initial setup (fetch submodules, check prerequisites)
make update

# Build for a specific camera (most common workflow)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make

# Fast incremental build (skips full rebuild)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make fast

# Release build (distclean + full build)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make release

# Configure kernel or packages interactively
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make menuconfig

# Save modified config back to the camera defconfig
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make saveconfig

# Edit a camera defconfig directly
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make edit-defconfig

# OTA update to a running camera (IP defaults to 192.168.1.10)
CAMERA=atom_cam2_t31x_gc2053_atbm6031 IP=192.168.1.42 make upgrade_ota
```

There are no automated test targets. Build validation happens via GitHub Actions (`.github/workflows/`).

## Repository Architecture

```
configs/cameras/<camera_name>/   # Per-camera defconfigs
configs/cameras-<GROUP>/         # Alternate config groups
package/<name>/                  # Custom Buildroot packages
overlay/                         # Root filesystem overlays (applied to all builds)
board/ingenic/                   # Board-level files (DTBs, patches, post-build scripts)
linux/                           # Linux kernel (submodule)
buildroot/                       # Buildroot source (submodule)
scripts/                         # Helper scripts (dep_check.sh, select_camera.sh)
thingino.mk                      # SOC/kernel/flash layout definitions
board.mk                         # Camera config loading and variable exports
external.mk                      # Includes all package/*.mk files automatically
```

Output lands in `output/<branch>/<camera>-<kernel_version>/`.

## Camera Naming Convention

Camera config directories and defconfigs follow this pattern:

```
<brand>_<model>_<soc>_<sensor>_<wifi_chip>
```

Example: `atom_cam2_t31x_gc2053_atbm6031`  
Defconfig: `configs/cameras/atom_cam2_t31x_gc2053_atbm6031/atom_cam2_t31x_gc2053_atbm6031_defconfig`

The first line of each defconfig is a human-readable `# NAME:` comment; the second line lists `# FRAG:` (config fragments used).

## Key Conventions

### Adding or Modifying a Package

Each package lives in `package/<name>/` and requires:
- `<name>.mk` — standard Buildroot package makefile (defines `<NAME>_VERSION`, `<NAME>_SITE`, install commands, etc.)
- `Config.in` — Kconfig menu entry
- Must be referenced in `package/Config.in` or a parent `Config.in` to appear in menuconfig

The `external.mk` auto-includes all `package/*/*.mk` files.

### SOC and Kernel Variables

`thingino.mk` maps `BR2_SOC_INGENIC_*` Kconfig symbols to runtime variables used throughout the build:
- `SOC_FAMILY` (e.g., `t31`), `SOC_MODEL` (e.g., `t31x`), `SOC_RAM_MB`
- `KERNEL_VERSION` (either `3.10` or `4.4`)
- `BR2_XBURST_1` / `BR2_XBURST_2` — CPU architecture variant

Packages that differ between kernel versions gate on `$(KERNEL_VERSION)`:
```makefile
ifeq ($(KERNEL_VERSION),3.10)
    PKG_CFLAGS += -DCONFIG_KERNEL_3_10
endif
```

### Overlay Files

Files placed under `overlay/` are merged into the target root filesystem. Subdirectories mirror the target path:
- `overlay/etc/` → `/etc/`
- `overlay/etc/init.d/` → `/etc/init.d/` (init scripts)
- `overlay/usr/` → `/usr/`

Init scripts follow Buildroot's `SXXname` naming convention (where `XX` is the start order).

### Config Fragments

Defconfigs reference reusable fragments (listed in `# FRAG:` header). Fragments are stored under `configs/` and merged by the build system. Common fragments include toolchain, rootfs, kernel, and SOC-specific settings.

### Dependency Check

Running `make` on a fresh checkout triggers `scripts/dep_check.sh` which validates host tool availability. It is skipped when `WORKFLOW=1` (CI) or when `.prereqs.done` exists. The repo path must not contain spaces.

### CI / GitHub Actions

Workflows are in `.github/workflows/`. Key workflows:
- `firmware.yaml` / `firmware-stable.yml` — build all camera configs
- `toolchain-x86_64.yaml` / `toolchain-aarch64.yaml` — toolchain builds
- `ver-check.yaml` — upstream version checks

CI sets `WORKFLOW=1` to skip the interactive camera selection and dependency check.

### Overrides

Local development unilizes override sources defined in `local.mk` file and stored in `overrides/` directory.

### SSH

Thingino used dropbear for ssh. Uploading files with `scp` requires `-O` flag.

