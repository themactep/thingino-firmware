# Docker Build Quick Reference

Quick reference for building Thingino firmware in containers.

## One-Command Build

```bash
./docker-build.sh
```

Then select a camera using **fzf** (fuzzy finder):
- Type to filter (e.g., "atom", "eufy", "t31x")
- Arrow keys to navigate
- Enter to select

If fzf is not installed, falls back to whiptail/dialog menu.

## Common Commands

```bash
# Build firmware (fast parallel)
./docker-build.sh

# Debug build (slow serial, stops at first error)
./docker-build.sh dev

# Interactive shell
./docker-build.sh shell

# Configuration
./docker-build.sh menuconfig

# Clean build
./docker-build.sh clean

# Show info
./docker-build.sh info
```

## First Time Setup

```bash
# Install Podman (recommended)
sudo apt update && sudo apt install podman

# Install fzf for better camera selection (optional but recommended)
sudo apt install fzf

# Build firmware
./docker-build.sh
```

Select your camera using fzf (type to filter) or menu navigation.

## File Locations

- **Dockerfile**: `Dockerfile`
- **Make include**: `Makefile.docker`
- **Wrapper script**: `docker-build.sh`
- **Build outputs**: `output/images/`
- **Download cache**: `$HOME/dl/`

## Troubleshooting

```bash
# Build crashed? Run debug build to find the error
./docker-build.sh dev

# Rebuild container image
./docker-build.sh rebuild-image

# Check configuration
./docker-build.sh info

# Permission issues - rebuild with correct UID
./docker-build.sh rebuild-image
```

### When Build Crashes

If your fast parallel build crashes, rerun with `dev` mode:

```bash
./docker-build.sh dev
```

This uses serial compilation which:
- Stops at the exact error
- Shows complete error output
- Makes debugging much easier

## See Also

Full documentation: `docs/buildroot/docker-build-environment.md`
