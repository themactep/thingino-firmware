# Docker/Podman Build Environment

This directory contains a containerized build environment for Thingino firmware, providing a reproducible build setup independent of the host operating system.

## Quick Start

### Prerequisites

Install either Podman (recommended) or Docker:

**Podman** (recommended - rootless):
```bash
sudo apt update
sudo apt install podman
```

**Docker**:
```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

### Build Firmware in Container

```bash
# Build firmware (non-interactive)
./docker-build.sh

# Or use make
make -f Makefile.docker docker-build-firmware
```

### Interactive Development

```bash
# Open shell in container
./docker-build.sh shell

# Inside the container, run standard make commands
make menuconfig
make
```

## Features

- **Reproducible Builds**: Same environment across all systems
- **Host-Independent**: Works on any Linux distribution with Docker/Podman
- **Non-Interactive Mode**: Suitable for CI/CD pipelines
- **UID/GID Mapping**: Preserves file permissions on host
- **Persistent Downloads**: Buildroot download cache shared with host
- **No Root Required**: When using Podman

## Usage

### Wrapper Script (docker-build.sh)

The `docker-build.sh` script provides convenient access to common build tasks:

```bash
# Build firmware
./docker-build.sh build

# Run menuconfig
./docker-build.sh menuconfig

# Open interactive shell
./docker-build.sh shell

# Clean and rebuild
./docker-build.sh clean

# Run any make target
./docker-build.sh <target>

# Show configuration
./docker-build.sh info

# Rebuild container image
./docker-build.sh rebuild-image
```

### Makefile Integration (Makefile.docker)

Use make targets directly:

```bash
# Build container image
make -f Makefile.docker docker-build

# Build firmware in container
make -f Makefile.docker docker-build-firmware

# Interactive shell
make -f Makefile.docker docker-shell

# Configuration menus
make -f Makefile.docker docker-menuconfig
make -f Makefile.docker docker-linux-menuconfig
make -f Makefile.docker docker-busybox-menuconfig

# Clean build
make -f Makefile.docker docker-clean-build

# Remove container image
make -f Makefile.docker docker-clean

# Show configuration
make -f Makefile.docker docker-info
```

### Direct Container Commands

For advanced usage:

**Podman:**
```bash
# Build image
podman build --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) -t thingino-builder .

# Run build
podman run --rm --userns=keep-id \
  -v $(pwd):/home/builder/build \
  -v $HOME/dl:/home/builder/dl \
  thingino-builder make
```

**Docker:**
```bash
# Build image
docker build --build-arg USER_ID=$(id -u) --build-arg GROUP_ID=$(id -g) -t thingino-builder .

# Run build
docker run --rm --user $(id -u):$(id -g) \
  -v $(pwd):/home/builder/build \
  -v $HOME/dl:/home/builder/dl \
  thingino-builder make
```

## Configuration

### Environment Variables

    Variable            Default         Description
    ─────────────────────────────────────────────────────────────────────
    CONTAINER_ENGINE    auto-detected   Force specific engine: podman or docker
    DL_DIR              $HOME/dl        Buildroot download cache directory

### Build Arguments (Dockerfile)

    Argument     Default    Description
    ────────────────────────────────────────────────────────────
    USER_ID      1000       User ID for file ownership
    GROUP_ID     1000       Group ID for file ownership
    USERNAME     builder    Username inside container

## Volume Mounts

The container mounts two directories:

1. **Workspace** (`$(pwd)` → `/home/builder/build`)
   - The Thingino firmware source code
   - Build outputs are written here
   - Files owned by your host user

2. **Download Cache** (`$HOME/dl` → `/home/builder/dl`)
   - Buildroot package downloads
   - Shared across builds to save bandwidth
   - Persistent across container runs

## Workflow Examples

### Example 1: First-Time Build

```bash
# Clone repository
git clone https://github.com/themactep/thingino-firmware.git
cd thingino-firmware

# Build in container (image built automatically)
./docker-build.sh build
```

### Example 2: Development Workflow

```bash
# Start interactive shell
./docker-build.sh shell

# Inside container:
make menuconfig          # Configure
make                     # Build
make <package>-rebuild   # Rebuild specific package
exit

# Back on host - outputs in output/images/
ls output/images/
```

### Example 3: CI/CD Integration

```bash
#!/bin/bash
# ci-build.sh

set -e

# Build firmware non-interactively
./docker-build.sh build

# Verify outputs
ls -lh output/images/*.bin

# Upload artifacts
# ...
```

### Example 4: Custom Configuration

```bash
# Configure with specific defconfig
./docker-build.sh shell

# Inside container:
make <board>_defconfig
make menuconfig
make savedefconfig
exit

# Commit the defconfig
git add configs/
git commit -m "Update defconfig"
```

### Example 5: Clean Build

```bash
# Clean everything and rebuild
./docker-build.sh clean
```

## Troubleshooting

### Permission Issues

If files in `output/` are owned by wrong user:

**Cause**: UID/GID mismatch between host and container.

**Solution**: Rebuild image with correct IDs:
```bash
./docker-build.sh rebuild-image
```

### Container Image Not Found

```bash
Error: thingino-builder:latest: image not found
```

**Solution**: Build the image:
```bash
make -f Makefile.docker docker-build
```

### Podman/Docker Not Found

```bash
[ERROR] Neither Podman nor Docker found
```

**Solution**: Install container engine (see Prerequisites).

### Out of Disk Space

Container builds require significant space (~20GB for full build).

**Solution**:
- Free up space on host
- Clean old container images: `podman system prune -a`
- Clean buildroot cache: `rm -rf $HOME/dl/*`

### Network Issues in Container

Some corporate networks block container registries.

**Solution**:
- Configure proxy: Edit `Dockerfile` to add `ENV http_proxy=...`
- Use mirror: Modify base image in `Dockerfile`

### Slow Builds

First build downloads and compiles everything.

**Optimization**:
- Use faster storage (SSD)
- Increase `BR2_JLEVEL` (CPU cores)
- Share download cache (`DL_DIR`)
- Use ccache (already configured)

## Advanced Usage

### Custom Download Directory

```bash
# Use specific download directory
DL_DIR=/path/to/cache ./docker-build.sh build
```

### Force Specific Engine

```bash
# Force Docker even if Podman is available
CONTAINER_ENGINE=docker ./docker-build.sh build
```

### Multiple Configurations

```bash
# Terminal 1: Build for board A
./docker-build.sh shell
make boardA_defconfig && make

# Terminal 2: Build for board B (different workspace)
cd ../thingino-firmware-boardB
./docker-build.sh shell
make boardB_defconfig && make
```

### Updating Base Image

```bash
# Get latest Debian testing base
./docker-build.sh rebuild-image

# Or manually
make -f Makefile.docker docker-clean
make -f Makefile.docker docker-build
```

## Comparison with Host Build

    Aspect            Container Build              Host Build
    ─────────────────────────────────────────────────────────────────────────
    Dependencies      Isolated in container        Install on host
    Reproducibility   ✅ Same across systems       ⚠️ Depends on host
    Setup Time        Image build once             Install packages
    Disk Space        ~10GB (image + build)        ~8GB (build only)
    Performance       ~5% overhead                 Native speed
    Isolation         ✅ Safe from host            ⚠️ Affects host
    CI/CD             ✅ Ideal                     Requires setup

## Files

    File                 Description
    ───────────────────────────────────────────────────────────────────────
    Dockerfile           Container image definition
    Makefile.docker      Make targets for container builds
    docker-build.sh      Convenience wrapper script
    .dockerignore        Files excluded from container build context

## Container Image Details

**Base Image**: `debian:testing`

**Installed Packages**:
- Build tools: gcc, make, cmake, autoconf, etc.
- Buildroot dependencies: flex, bison, ncurses, etc.
- Cross-compiler: gcc-mipsel-linux-gnu
- Utilities: git, vim, wget, rsync, etc.
- Python: python3 with jinja2, jsonschema, yaml

**User**: Non-root user (builder) with matching UID/GID

**Working Directory**: `/home/builder/build`

## Security Considerations

- Container runs as non-root user
- No privileged access required
- Host filesystem access limited to mounted volumes
- Podman provides additional rootless security

## See Also

- [Buildroot Manual](https://buildroot.org/downloads/manual/manual.html)
- [Podman Documentation](https://docs.podman.io/)
- [Docker Documentation](https://docs.docker.com/)
- [Thingino Firmware](https://github.com/themactep/thingino-firmware)

## Contributing

When modifying the container setup:

1. Test with both Podman and Docker
2. Verify UID/GID mapping works correctly
3. Ensure non-interactive mode works
4. Update this documentation

## License

Same as Thingino firmware project.
