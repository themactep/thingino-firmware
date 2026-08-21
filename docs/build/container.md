# Docker/Podman Build Environment

Thingino firmware builds inside a container using a prebuilt image from
[ghcr.io/themactep/thingino-builder-image](https://github.com/themactep/thingino-builder-image).
The image is pulled automatically on first run — no local build of the
container image is required.

## Quick Start

### Prerequisites

Install either Podman (recommended) or Docker:

**Podman** (recommended — rootless):
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
./build-container.sh

# Or use make
make -f Makefile.container container-build-firmware
```

### Interactive Development

```bash
# Open shell in container
./build-container.sh shell

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
- **Prebuilt Image**: No local container image build needed

## Usage

### Wrapper Script (build-container.sh)

The `build-container.sh` script provides convenient access to common build tasks:

```bash
# Build firmware
./build-container.sh build

# Run menuconfig
./build-container.sh menuconfig

# Open interactive shell
./build-container.sh shell

# Clean and rebuild
./build-container.sh cleanbuild

# Run any make target
./build-container.sh <target>

# Show configuration
./build-container.sh info

# Pull latest container image
./build-container.sh rebuild-image
```

### Makefile Integration (Makefile.container)

Use make targets directly:

```bash
# Pull container image
make -f Makefile.container container-pull

# Build firmware in container
make -f Makefile.container container-build-firmware

# Interactive shell
make -f Makefile.container container-shell

# Configuration menus
make -f Makefile.container container-menuconfig
make -f Makefile.container container-linux-menuconfig
make -f Makefile.container container-busybox-menuconfig

# Clean build
make -f Makefile.container container-clean-build

# Remove cached container image
make -f Makefile.container container-clean

# Show configuration
make -f Makefile.container container-info
```

### Direct Container Commands

For advanced usage, you can run the prebuilt image directly:

**Podman:**
```bash
podman run --rm --userns=keep-id \
  -v $(pwd):/workspace \
  -v dl:/home/builder/dl \
  -w /workspace \
  ghcr.io/themactep/thingino-builder-image:latest \
  make
```

**Docker:**
```bash
docker run --rm --user $(id -u):$(id -g) \
  -v $(pwd):/workspace \
  -v dl:/home/builder/dl \
  -w /workspace \
  ghcr.io/themactep/thingino-builder-image:latest \
  make
```

## Configuration

### Environment Variables

    Variable            Default         Description
    ─────────────────────────────────────────────────────────────────────
    CONTAINER_ENGINE    auto-detected   Force specific engine: podman or docker
    DL_DIR              dl              Buildroot download cache directory
    CONTAINER_TAG          latest          Image tag (use 'local' for air-gapped)

## Volume Mounts

The container mounts two directories:

1. **Workspace** (`$(pwd)` → `/workspace`)
   - The Thingino firmware source code
   - Build outputs are written here
   - Files owned by your host user

2. **Download Cache** (`dl/` → `/home/builder/dl`)
   - Buildroot package downloads
   - Shared across builds to save bandwidth
   - Persistent across container runs

## Workflow Examples

### Example 1: First-Time Build

```bash
# Clone repository
git clone --recurse-submodules https://github.com/themactep/thingino-firmware.git
cd thingino-firmware

# Build in container (image pulled automatically)
./build-container.sh build
```

### Example 2: Development Workflow

```bash
# Start interactive shell
./build-container.sh shell

# Inside container:
make menuconfig          # Configure
make                     # Build
make <package>-rebuild   # Rebuild specific package
exit

# Back on host — outputs in output/images/
ls output/images/
```

### Example 3: CI/CD Integration

```bash
#!/bin/bash
# ci-build.sh

set -e

# Build firmware non-interactively
CAMERA=wyze_cam_v3 ./build-container.sh build

# Verify outputs
ls -lh output/images/*.bin
```

## Air-Gapped Builds

The prebuilt image is pulled from GitHub Container Registry by default. If
you need to build in an environment without internet access, build the
container image locally from the
[thingino-builder-image](https://github.com/themactep/thingino-builder-image)
repository:

```bash
git clone https://github.com/themactep/thingino-builder-image.git
cd thingino-builder-image
podman build -t thingino-builder-image:local .
```

Then point the build scripts at your local image:

```bash
CONTAINER_TAG=local ./build-container.sh build
```

## Troubleshooting

### Permission Issues

If files in `output/` are owned by wrong user:

**Cause**: UID/GID mismatch between host and container.

**Solution**: Rebuild image with correct IDs:
```bash
./build-container.sh rebuild-image
```

### Container Image Not Found

```bash
Error: image not found
```

**Solution**: Pull the image:
```bash
make -f Makefile.container container-pull
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
- Clean buildroot cache: `rm -rf dl/*`

### Slow Builds

First build downloads and compiles everything.

**Optimization**:
- Use faster storage (SSD)
- Increase `BR2_JLEVEL` (CPU cores)
- Share download cache (`DL_DIR`)
- Use ccache (already configured)

## Comparison with Host Build

    Aspect            Container Build              Host Build
    ─────────────────────────────────────────────────────────────────────────
    Dependencies      Isolated in container        Install on host
    Reproducibility   Same across systems          Depends on host
    Setup Time        Image pulled once            Install packages
    Disk Space        ~10GB (image + build)        ~8GB (build only)
    Performance       ~5% overhead                 Native speed
    Isolation         Safe from host               Affects host
    CI/CD             Ideal                        Requires setup

## Files

    File                 Description
    ───────────────────────────────────────────────────────────────────────
    Makefile.container      Make targets for container builds
    build-container.sh      Convenience wrapper script

## Container Image Details

**Image**: `ghcr.io/themactep/thingino-builder-image:latest`

**Base**: Ubuntu 26.04 with build dependencies pre-installed.

**Source**: [github.com/themactep/thingino-builder-image](https://github.com/themactep/thingino-builder-image)

For air-gapped environments, build the image locally from the source
repository (see Air-Gapped Builds above).

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
- [Thingino Builder Image](https://github.com/themactep/thingino-builder-image)
