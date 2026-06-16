# Docker Build Quick Reference

Quick reference for building Thingino firmware in containers.

## One-Command Build

```bash
./build-container.sh
```

Then select a camera using **fzf** (fuzzy finder):
- Type to filter (e.g., "atom", "eufy", "t31x")
- Arrow keys to navigate
- Enter to select

If fzf is not installed, falls back to whiptail/dialog menu.

## Common Commands

```bash
# Build firmware (fast parallel)
./build-container.sh

# Debug build (slow serial, stops at first error)
./build-container.sh dev

# Interactive shell
./build-container.sh shell

# Configuration
./build-container.sh menuconfig

# Clean build
./build-container.sh cleanbuild

# Show info
./build-container.sh info

# Pull latest container image
./build-container.sh rebuild-image
```

## First Time Setup

```bash
# Install Podman (recommended)
sudo apt update && sudo apt install podman

# Install fzf for better camera selection (optional but recommended)
sudo apt install fzf

# Build firmware (image pulled automatically)
./build-container.sh
```

Select your camera using fzf (type to filter) or menu navigation.

## File Locations

- **Make include**: `Makefile.container`
- **Wrapper script**: `build-container.sh`
- **Build outputs**: `output/<branch>/<camera>/images/`
- **Download cache**: `dl/`

## Container Image

The build uses a prebuilt image from
[ghcr.io/themactep/thingino-builder-image](https://github.com/themactep/thingino-builder-image).
It is pulled automatically on first run.

For air-gapped builds, build locally from the
[thingino-builder-image](https://github.com/themactep/thingino-builder-image)
repo and use `CONTAINER_TAG=local`.

## Troubleshooting

```bash
# Build crashed? Run debug build to find the error
./build-container.sh dev

# Pull latest container image
./build-container.sh rebuild-image

# Check configuration
./build-container.sh info
```

### When Build Crashes

If your fast parallel build crashes, rerun with `dev` mode:

```bash
./build-container.sh dev
```

This uses serial compilation which:
- Stops at the exact error
- Shows complete error output
- Makes debugging much easier

## See Also

Full documentation: `docs/buildroot/docker-build-environment.md`
