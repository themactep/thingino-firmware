Makefile Guide
==============

This document provides comprehensive documentation for working with the Thingino firmware build system. The Makefile is the primary interface for building firmware, managing configurations, and interacting with packages.

## Table of Contents

- [Quick Start](#quick-start)
- [Environment Variables](#environment-variables)
- [Main Build Targets](#main-build-targets)
- [Configuration Management](#configuration-management)
- [Package Management](#package-management)
- [Buildroot Integration](#buildroot-integration)
- [Firmware Deployment](#firmware-deployment)
- [Shared Host Directory](#shared-host-directory)
- [Advanced Usage](#advanced-usage)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### Basic Build Workflow

```bash
# 1. Select your camera profile
export CAMERA=t31_gc2053_lite

# 2. Build firmware (default: fast parallel build)
make

# 3. Flash to camera
make upgrade_ota IP=192.168.1.10
```

### Common Commands

```bash
make                   # Build firmware (clean + parallel)
make dev               # Serial build for debugging
make fast              # Fast incremental build (no clean)
make clean             # Clean build artifacts
make distclean         # Complete clean (removes OUTPUT_DIR)
```

---

## Environment Variables

### Camera Selection

**`CAMERA`** - Specifies which camera profile to build
- Required for most build operations
- Camera profiles are located in `configs/cameras/` or `configs/cameras-*/`
- Example: `CAMERA=t31_gc2053_lite`

**`GROUP`** - Camera configuration group
- `github` → `configs/github/`
- (empty) → `configs/cameras/` (default)
- `exp` → `configs/cameras-exp/`
- Custom: `GROUP=exp` → `configs/cameras-exp/`

### Network Configuration

**`IP`** - Camera IP address for OTA updates (default: `192.168.1.10`)
```bash
make upgrade_ota IP=192.168.88.111
```

**`TFTP_IP_ADDRESS`** - TFTP server IP (default: `192.168.1.254`)

### Build Paths

**`BR2_DL_DIR`** - Buildroot downloads directory (default: `~/dl`)
```bash
export BR2_DL_DIR=/path/to/shared/downloads
make
```

**`OUTPUT_DIR`** - Build output directory
- Auto-generated based on `CAMERA` and git branch
- Default pattern: `~/output-<branch>/<camera>`
- Can be overridden manually

### Advanced Variables

**`SDCARD_DEVICE`** - SD card device for flashing (default: `/dev/sdf`)

**`RELEASE`** - Build release firmware without local overrides
```bash
make release  # Sets RELEASE=1
```

**`WORKFLOW`** - Skip dependency checks (used in CI/CD)

---

## Main Build Targets

### Standard Build Targets

#### `all` (default)
Fast parallel incremental build - the recommended default.
```bash
make all
# or simply
make
```
Equivalent to: `defconfig build_fast pack`

#### `dev`
Serial build for debugging compilation issues. Runs single-threaded to make error messages clearer.
```bash
make dev
```
Equivalent to: `defconfig build pack`

#### `fast`
Fast incremental build without cleaning. Useful for rapid iteration.
```bash
make fast
```
Equivalent to: `defconfig build_fast pack`

#### `cleanbuild`
Complete clean build with parallel compilation. Removes all previous build artifacts first.
```bash
make cleanbuild
```
Equivalent to: `distclean defconfig build_fast pack`

#### `release`
Build release firmware without local configuration overrides.
```bash
make release
```
Disables `local.fragment` and `local.mk` inclusion.

### Build Process Targets

#### `bootstrap`
Install system dependencies required for building.
```bash
make bootstrap
```
Runs `scripts/dep_check.sh` to verify and install build prerequisites.

#### `build`
Serial build (single-threaded) without cleaning.
```bash
make build
```

#### `build_fast`
Parallel build using all available CPU cores.
```bash
make build_fast
```
Uses `make -j$(nproc)` internally.

#### `pack`
Assemble final firmware images from built components.
```bash
make pack
```
Creates:
- `thingino-<camera>.bin` (full image with bootloader)
- `thingino-<camera>-update.bin` (update image without bootloader)

#### `repack`
Remove binary files and reassemble firmware images.
```bash
make repack
```
Useful when modifying overlay files without rebuilding everything.

### Cleanup Targets

#### `clean`
Remove target directory and generated images, but preserve compiled packages.
```bash
make clean
```
Removes:
- `$(OUTPUT_DIR)/target/`
- `$(OUTPUT_DIR)/config/`
- `$(OUTPUT_DIR)/extras/`
- Firmware binaries

#### `clean-nfs-debug`
Clean camera-specific NFS debug artifacts (when debug builds are enabled).
```bash
make clean-nfs-debug
```

#### `distclean`
Complete cleanup - removes entire output directory.
```bash
make distclean
```
**Warning**: This deletes all build artifacts. Next build will be from scratch.

#### `clean-config`
Remove only configuration files.
```bash
make clean-config
```

---

## Configuration Management

### Configuration Files

Thingino uses a layered configuration system:

1. **Fragment files** (`configs/fragments/*.fragment`) - Modular config pieces
2. **Module config** - SoC/sensor specific configuration
3. **Camera config** - Camera-specific overrides
4. **Local overrides** (optional, ignored in release builds):
   - `user/local.fragment` - Local Buildroot config additions
   - `user/local.config` - Local system config
   - `user/local.uenv.txt` - Local U-Boot environment
   - `local.mk` - Local Makefile overrides

### Configuration Targets

#### `defconfig`
Configure buildroot with auto-detection of changes.
```bash
make defconfig
```
Only regenerates if configuration files have been modified.

#### `check-config`
Check if configuration needs regeneration without building.
```bash
make check-config
```

#### `force-config`
Force configuration regeneration regardless of timestamps.
```bash
make force-config
```

#### `show-config-deps`
Display configuration input files and dependency tracking information.
```bash
make show-config-deps
```

### Interactive Configuration

#### `menuconfig`
Launch ncurses-based Buildroot configuration menu.
```bash
make menuconfig
```

#### `nconfig`
Alternative ncurses configuration interface.
```bash
make nconfig
```

#### `saveconfig`
Save menuconfig changes back to defconfig file.
```bash
make saveconfig
```

### Editing Configuration Files

#### `edit`
Interactive menu to edit various configuration files.
```bash
make edit
```
Presents a dialog menu with options:
1. Camera Config (defconfig)
2. Module Config
3. System Config
4. Camera U-Boot Environment
5. Local Fragment
6. Local Config
7. Local Makefile
8. Local U-Boot Environment

#### Direct Edit Targets

```bash
make edit-defconfig      # Edit camera's defconfig
make edit-config         # Edit system config
make edit-uenv           # Edit U-Boot environment
make edit-localfragment  # Edit local.fragment
make edit-localconfig    # Edit local.config
make edit-localmk        # Edit local.mk
make edit-localuenv      # Edit local.uenv.txt
```

The system will use the first available editor from: `nano`, `vim`, `vi`, `ed`

---

## Package Management

### Rebuilding Packages

#### `rebuild-<package>`
Clean and rebuild a specific package.
```bash
make rebuild-telegrambot
make rebuild-prudynt-t
make rebuild-linux
```
Equivalent to: `<package>-dirclean` + `<package>`

### Buildroot Package Targets (with `br-` prefix)

For backward compatibility, you can use the `br-` prefix to explicitly call buildroot targets:

```bash
make br-telegrambot           # Build telegrambot package
make br-telegrambot-dirclean  # Clean telegrambot build files
make br-linux-menuconfig      # Configure kernel
make br-busybox-menuconfig    # Configure busybox
```

### Direct Buildroot Targets (NEW)

**As of the latest update**, you can now call buildroot targets directly **without the `br-` prefix**:

```bash
make telegrambot              # Build telegrambot package
make telegrambot-dirclean     # Clean telegrambot build files
make linux-menuconfig         # Configure kernel
make busybox-menuconfig       # Configure busybox
make linux-rebuild            # Rebuild kernel
```

#### How It Works

The Makefile includes a catch-all pattern rule that forwards any undefined target to buildroot:

```makefile
%: check-config
	$(BR2_MAKE) $@
```

This means:
- If a target is defined in the Thingino Makefile, it runs locally
- If not found, it's automatically forwarded to buildroot
- The `br-` prefix still works for explicit clarity

#### Common Buildroot Targets

```bash
# Kernel
make linux-menuconfig         # Configure kernel
make linux-rebuild            # Rebuild kernel
make linux-dirclean           # Clean kernel build

# Busybox
make busybox-menuconfig       # Configure busybox
make busybox-rebuild          # Rebuild busybox

# Packages
make <package>                # Build a package
make <package>-rebuild        # Rebuild a package
make <package>-dirclean       # Clean a package
make <package>-reconfigure    # Reconfigure a package
```

---

## Buildroot Integration

### Buildroot Submodule

The buildroot submodule is located at `buildroot/` and is managed automatically.

```bash
# Initialize buildroot submodule
git submodule init
git submodule update

# Or let the Makefile do it
make buildroot/Makefile
```

### Buildroot Commands

The `BR2_MAKE` variable is used internally to call buildroot:

```bash
BR2_MAKE = $(MAKE) -C $(BR2_EXTERNAL)/buildroot \
           BR2_EXTERNAL=$(BR2_EXTERNAL) \
           O=$(OUTPUT_DIR) \
           BR2_DL_DIR=$(BR2_DL_DIR)
```

### Source Downloads

```bash
# Download sources for all packages
make source

# Download buildroot cache bundle
make download-cache
```

### SDK and Toolchain

```bash
# Build SDK (fast parallel)
make sdk

# Build toolchain (serial)
make toolchain
```

---

## Firmware Deployment

### Over-The-Air (OTA) Updates

#### `upgrade_ota`
Flash full firmware image (includes bootloader).
```bash
make upgrade_ota IP=192.168.1.10
```
**Warning**: Flashing bootloader can brick the camera if interrupted.

#### `update_ota`
Flash kernel and rootfs only (no bootloader).
```bash
make update_ota IP=192.168.1.10
```
Safer option for regular updates.

#### `upboot_ota`
Flash bootloader only.
```bash
make upboot_ota IP=192.168.1.10
```

### TFTP Upload

```bash
make upload_tftp TFTP_IP_ADDRESS=192.168.1.254
```

Uploads the full firmware image to TFTP server for network installation.

---

## Shared Host Directory

The shared host directory feature allows multiple camera builds to reuse the same host tools, significantly speeding up builds and saving disk space.

### How It Works

- First build: Creates `host-shared/` with host tools
- Subsequent builds: Automatically reuse `host-shared/` instead of rebuilding
- Buildroot version is tracked to detect incompatibilities

### Usage

#### `populate-shared-host`
Manually populate the shared host directory from current build.
```bash
# First, build any camera
make CAMERA=t31_gc2053_lite

# Then populate shared host
make populate-shared-host
```

#### `auto-populate-shared-host`
Automatically called after successful builds to update the shared host directory.

#### `check-shared-host`
Check the status of the shared host directory.
```bash
make check-shared-host
```
Shows:
- Whether shared host exists
- Buildroot version compatibility
- Last update timestamp
- Directory size

### Version Compatibility

The system tracks the buildroot git commit hash:
- If buildroot version changes, you'll get a warning
- Auto-population is skipped when versions don't match
- Manual rebuild recommended after buildroot updates:
  ```bash
  rm -rf host-shared
  make CAMERA=any_camera
  make populate-shared-host
  ```

---

## Advanced Usage

### Repository Updates

#### `update`
Update repository and submodules (excludes buildroot patches).
```bash
make update
```
- Pulls latest changes with rebase
- Updates submodules
- Makes buildroot read-only to prevent accidental changes

#### `update_manual`
Download latest buildroot manuals.
```bash
make update_manual
```
Downloads:
- `docs/buildroot/manual.pdf`
- `docs/buildroot/manual.txt`

### Information and Debugging

#### `info`
Display detailed build configuration information.
```bash
make info
```
Shows:
- Architecture details
- SOC family and model
- Kernel version and sources
- Sensor models
- Flash size
- Toolchain information
- SDK versions

#### `agent-info`
Show rebuild conventions and key variables (useful for automation/assistants).
```bash
make agent-info
```

#### `show-vars`
Print key build variables.
```bash
make show-vars
```
Displays:
- `BR2_EXTERNAL`
- `OUTPUT_DIR`
- `BR2_DL_DIR`
- `CAMERA_SUBDIR`
- `CAMERA`
- `HOST_DIR`
- `BR2_MAKE`

#### `help`
Display help message with common targets.
```bash
make help
```

---

## Troubleshooting

### Configuration Issues

**Problem**: Configuration seems outdated after editing fragments
```bash
# Force regeneration
make force-config

# Or clean and rebuild
make distclean
make
```

**Problem**: Want to see what configuration files are being used
```bash
make show-config-deps
```

### Build Issues

**Problem**: Compilation errors are hard to read
```bash
# Use serial build for clearer error messages
make dev
```

**Problem**: Package won't rebuild properly
```bash
# Force clean rebuild of specific package
make rebuild-<package>

# Or manually
make <package>-dirclean
make <package>
```

**Problem**: Kernel configuration changes not taking effect
```bash
# Clean kernel and rebuild
make linux-dirclean
make linux-menuconfig
make linux
```

### Output Directory Issues

**Problem**: Want to change output directory
```bash
# Set OUTPUT_DIR before building
export OUTPUT_DIR=/path/to/custom/output
make
```

**Problem**: Build artifacts from different branches interfering
```bash
# The Makefile automatically segregates by branch:
# - master → ~/output/<camera>
# - other → ~/output-<branch>/<camera>

# For complete isolation, use distclean
make distclean
```

### Shared Host Issues

**Problem**: Buildroot version mismatch warning
```bash
# Check status
make check-shared-host

# Rebuild shared host
rm -rf host-shared
make CAMERA=any_camera
make populate-shared-host
```

**Problem**: Want to disable shared host
```bash
# Simply remove or rename it
mv host-shared host-shared.backup

# Next build will use per-build host directory
```

### Package Issues

**Problem**: Package source download fails
```bash
# Download sources separately
make source

# Or download buildroot cache bundle
make download-cache
```

**Problem**: Need to reconfigure package
```bash
make <package>-reconfigure
```

**Problem**: Want to see all available targets for a package
```bash
# Most buildroot packages support:
make <package>              # Build
make <package>-rebuild      # Rebuild
make <package>-reconfigure  # Reconfigure
make <package>-dirclean     # Clean
make <package>-menuconfig   # Configure (if supported)
```

### Firmware Size Issues

**Problem**: Firmware too large for flash
```bash
# Check partition layout
make pack

# The output shows a table with sizes and alignment
# Look for "OVERSIZE" or "FINE" in the figlet output

# Solutions:
# - Disable unnecessary packages in menuconfig
# - Use external storage for extras partition
# - Use larger flash chip
```

**Problem**: Extras partition too small
```bash
# Check the pack output - you'll see "EXTRAS PARTITION IS TOO SMALL"

# This happens when:
# EXTRAS_PARTITION_SIZE < 163840 bytes (5 × 32KB blocks)

# Solutions:
# - Reduce kernel or rootfs size
# - Disable packages that install to /opt/
```

---

## Makefile Structure

### Key Variables

- **Paths**: `BR2_EXTERNAL`, `OUTPUT_DIR`, `BR2_DL_DIR`, `HOST_DIR`
- **Camera**: `CAMERA`, `CAMERA_SUBDIR`, `GROUP`
- **Network**: `IP`, `CAMERA_IP_ADDRESS`, `TFTP_IP_ADDRESS`
- **Git Info**: `GIT_BRANCH`, `GIT_HASH`, `GIT_DATE`, `BUILD_DATE`
- **Sizes**: `SIZE_*` constants for partition alignment
- **Partitions**: `*_OFFSET`, `*_PARTITION_SIZE` for firmware layout

### Included Makefiles

1. **`board.mk`** - Camera board selection and validation
2. **`thingino.mk`** - Core Thingino-specific build logic
3. **`local.mk`** (optional) - Local build customizations
4. **`external.mk`** - Buildroot external package definitions

### Partition Layout

Firmware is assembled from multiple partitions:

| Partition | Offset     | Size    | Contents                |
|-----------|------------|---------|-------------------------|
| U-Boot    | 0x000000   | 256 KB  | Bootloader              |
| UB_ENV    | 0x040000   | 32 KB   | U-Boot environment      |
| CONFIG    | 0x048000   | 224 KB  | Configuration (JFFS2)   |
| KERNEL    | 0x080000   | Dynamic | Linux kernel (uImage)   |
| ROOTFS    | Dynamic    | Dynamic | Root filesystem (SquashFS) |
| EXTRAS    | Dynamic    | Dynamic | Optional packages (JFFS2)  |

Sizes are 32KB-aligned for JFFS2 compatibility.

---

## Best Practices

### Development Workflow

1. **Use incremental builds** during development:
   ```bash
   make fast  # or just `make` for the first build
   ```

2. **Use `dev` for debugging** compilation issues:
   ```bash
   make dev
   ```

3. **Use `cleanbuild` when switching cameras** or after major changes:
   ```bash
   make cleanbuild
   ```

### Configuration Management

1. **Never edit `.config` directly** - use `menuconfig` or edit defconfig files
2. **Save changes** after menuconfig:
   ```bash
   make menuconfig
   make saveconfig
   ```
3. **Use fragments** for modular configurations instead of duplicating full configs
4. **Test with `release`** before committing to ensure local overrides aren't required

### Package Development

1. **Use `rebuild-<package>`** for iterative package development
2. **Clean build** after modifying package makefiles:
   ```bash
   make <package>-dirclean
   make <package>
   ```
3. **Check package dependencies** in menuconfig before building

### Repository Hygiene

1. **Regular updates**:
   ```bash
   make update
   ```
2. **Don't modify buildroot** - use overrides in `package/thingino-*/`
3. **Keep local.* files out of git** - they're in `.gitignore`

---

## Quick Reference

### Most Used Commands

```bash
# Build
make                           # Default build
make dev                       # Debug build
make CAMERA=t31_gc2053_lite    # Specify camera

# Configuration
make menuconfig               # Configure buildroot
make saveconfig               # Save menuconfig changes

# Packages
make rebuild-<package>        # Rebuild package
make <package>-menuconfig     # Configure package (kernel, busybox, etc.)

# Deploy
make upgrade_ota IP=x.x.x.x   # Flash full firmware
make update_ota IP=x.x.x.x    # Flash kernel+rootfs only

# Clean
make clean                    # Clean build artifacts
make distclean                # Complete clean

# Info
make info                     # Show build info
make help                     # Show help
```

### Environment Variable Cheat Sheet

```bash
export CAMERA=t31_gc2053_lite        # Camera profile
export GROUP=github                  # Camera group
export IP=192.168.1.10               # Camera IP
export BR2_DL_DIR=/path/to/downloads # Download cache
export OUTPUT_DIR=/custom/path       # Build output
```

---

For more information, see:
- [Buildroot Documentation](buildroot.md)
- [Firmware Structure](firmware-image-structure.md)
- [Best Practices](best-practices.md)
