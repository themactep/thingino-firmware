# Podman/Docker Build Container

Thingino firmware builds inside a container using a prebuilt image from
[ghcr.io/themactep/thingino-builder-image](https://github.com/themactep/thingino-builder-image).
The image is pulled automatically on first run.

## Quick Start

```bash
# Build firmware (shows camera selection menu)
./build-container.sh

# Or open interactive shell
./build-container.sh shell
```

## Files

    File                Purpose
    ──────────────────────────────────────────────────────────────────
    Makefile.container     Make targets for container builds
    build-container.sh     Convenient wrapper script

## Common Commands

```bash
./build-container.sh                # Build firmware (parallel incremental)
./build-container.sh cleanbuild     # Clean + build from scratch (parallel)
./build-container.sh dev            # Debug build (serial incremental, V=1, stops at errors)
./build-container.sh shell          # Interactive shell
./build-container.sh menuconfig     # Configure build
./build-container.sh clean          # Clean build
./build-container.sh info           # Show configuration
./build-container.sh rebuild-image  # Pull latest container image
```

## Building Firmware

### Default Build (Incremental Parallel)

Simply run:

```bash
./build-container.sh
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

**Note:** Your camera selection is saved in `.selected_camera` and will be pre-selected next time.

### Clean Build (From Scratch)

To build from a completely clean state:

```bash
./build-container.sh cleanbuild
```

This does a **clean parallel build**:
- Runs `distclean` first (removes all build artifacts)
- Builds everything from scratch
- Uses all CPU cores for fast compilation
- Ensures a pristine build environment

### Debug Build (When Build Crashes)

If your build crashes with a parallel build error, rerun with:

```bash
./build-container.sh dev
```

This runs a **serial incremental build** with verbose output:
- Builds packages one by one (single-threaded)
- Stops immediately at the first error
- Shows exactly which package and file failed with V=1 (verbose)
- Resumes from where it left off (incremental)

### Camera Selection Issues

If fzf causes terminal display problems (half screen), disable it:

```bash
USE_FZF=0 ./build-container.sh
```

## Features

- Reproducible builds across all Linux distributions
- No host system dependency conflicts
- Works with both Podman and Docker
- Interactive camera selection with fzf (type to filter!)
- Non-interactive mode for CI/CD
- Preserves file ownership with UID/GID mapping
- Persistent download cache
- No root access required (with Podman)

## Requirements

Install either **Podman** (recommended) or **Docker**:

```bash
# Podman
sudo apt update && sudo apt install podman

# Docker
curl -fsSL https://get.docker.com | sudo sh
```

## Air-Gapped Builds

The prebuilt image is pulled from GitHub Container Registry. If you need to
build in an environment without internet access, build the container image
locally from the
[thingino-builder-image](https://github.com/themactep/thingino-builder-image)
repository:

```bash
git clone https://github.com/themactep/thingino-builder-image.git
cd thingino-builder-image
podman build -t thingino-builder-image:local .
```

Then use it by overriding the image tag:

```bash
CONTAINER_TAG=local make -f Makefile.container container-make
```

## Documentation

Full documentation: [docs/buildroot/docker-build-environment.md](docs/buildroot/docker-build-environment.md)

Quick reference: [docs/buildroot/docker-quick-reference.md](docs/buildroot/docker-quick-reference.md)
