# Docker/Podman Build Container

This directory contains the containerized build environment for Thingino firmware.

## Quick Start

```bash
# Build firmware (shows camera selection menu)
./docker-build.sh

# Or open interactive shell
./docker-build.sh shell
```

## Files

    File                Purpose
    ──────────────────────────────────────────────────────────────────
    Dockerfile          Container image definition
    Makefile.docker     Make targets for container builds
    docker-build.sh     Convenient wrapper script
    .dockerignore       Files excluded from build context

## Common Commands

```bash
./docker-build.sh                # Build firmware (parallel incremental)
./docker-build.sh cleanbuild     # Clean + build from scratch (parallel)
./docker-build.sh dev            # Debug build (serial incremental, V=1, stops at errors)
./docker-build.sh shell          # Interactive shell
./docker-build.sh menuconfig     # Configure build
./docker-build.sh clean          # Clean build
./docker-build.sh info           # Show configuration
./docker-build.sh rebuild-image  # Rebuild container image
```

## Building Firmware

### Default Build (Incremental Parallel)

Simply run:

```bash
./docker-build.sh
```

This does a **parallel incremental build**:
- Resumes from where you left off (if interrupted with Ctrl-C)
- Uses all CPU cores for fast compilation
- Only rebuilds what changed
- Perfect for iterative development

You'll get an interactive camera selector using **fzf** (if available):

- Type to filter camera list (exact match in order, e.g., "t20" shows t20* cameras)
- Use arrow keys to navigate
- Press Enter to select
- Press Esc to cancel
- **Press Ctrl-C to cancel the build at any time** (stops container within 2 seconds)

**Fallback options:** If fzf is not installed, the script automatically uses whiptail, dialog, or a simple numbered menu.

Example fzf usage:
```
Type to filter → "atom" shows only: atom_cam2_t31x_gc2053_atbm6031
Type to filter → "eufy" shows all Eufy camera models
Type to filter → "t31x" shows all T31X SoC cameras
```

**Note:** Your camera selection is saved in `.selected_camera` and will be pre-selected next time.

### Clean Build (From Scratch)

To build from a completely clean state:

```bash
./docker-build.sh cleanbuild
```

This does a **clean parallel build**:
- Runs `distclean` first (removes all build artifacts)
- Builds everything from scratch
- Uses all CPU cores for fast compilation
- Ensures a pristine build environment

**Use cleanbuild when:**
- You want to ensure a completely fresh build
- You've updated buildroot or external configs
- You're preparing a release build
- Something seems broken and you want to start fresh

### Debug Build (When Build Crashes)

If your build crashes with a parallel build error, rerun with:

```bash
./docker-build.sh dev
```

This runs a **serial incremental build** with verbose output:
- Builds packages one by one (single-threaded)
- Stops immediately at the first error
- Shows exactly which package and file failed with V=1 (verbose)
- Resumes from where it left off (incremental)
- Makes debugging compilation errors much easier

**Use dev mode when:**
- Your parallel build crashed and you need to find the exact error
- You're debugging a specific package compilation issue
- You need to see the complete error output without parallel noise

### Resuming After Interruption

The **default build is already incremental**! Just run:

```bash
./docker-build.sh
```

After pressing Ctrl-C or a crash, running the default command will:
- Resume from where you left off
- Only rebuild what's necessary
- Use parallel compilation

**No special command needed** - the default behavior is to continue where you stopped!

### Camera Selection Issues

If fzf causes terminal display problems (half screen), disable it:

```bash
USE_FZF=0 ./docker-build.sh
```

This will use whiptail/dialog scrollable menu instead (same as main Makefile).

## Documentation

Full documentation: [docs/buildroot/docker-build-environment.md](docs/buildroot/docker-build-environment.md)

Quick reference: [docs/buildroot/docker-quick-reference.md](docs/buildroot/docker-quick-reference.md)

## Features

- ✅ Reproducible builds across all Linux distributions
- ✅ No host system dependency conflicts
- ✅ Works with both Podman and Docker
- ✅ Interactive camera selection with fzf (type to filter!)
- ✅ Non-interactive mode for CI/CD
- ✅ Preserves file ownership with UID/GID mapping
- ✅ Persistent download cache
- ✅ No root access required (with Podman)

## Requirements

Install either **Podman** (recommended) or **Docker**:

```bash
# Podman
sudo apt update && sudo apt install podman

# Docker
curl -fsSL https://get.docker.com | sudo sh
```

## Integration with Makefile

The container setup is designed to work alongside the normal Makefile:

```bash
# Host build (traditional)
make

# Container build (reproducible)
./docker-build.sh
```

Both produce identical outputs but the container build is completely isolated from the host system.
