# Docker Build System - Quick Reference

## Features

### 1. Interactive Camera Selection
- **fzf-based selection** with fuzzy matching (exact substring mode)
- Camera selection **persists** between builds (stored in `.selected_camera`)
- ANSI escape codes properly stripped from selection

### 2. Build Modes
- **Default (./build-container.sh)**: Incremental parallel build — resumes from where it left off
- **Clean Build**: `./build-container.sh cleanbuild` — Clean slate + parallel build
- **Dev Build**: `./build-container.sh dev` — Serial build with V=1 verbose output (debugging)
- **Shell**: `./build-container.sh shell` — Interactive container shell

### 3. Signal Handling
- **Ctrl-C properly stops builds** — traps SIGINT and cleans up container processes

### 4. Output Persistence
- Build artifacts saved to `output/<branch>/<camera>/images/` on host
- Volume mounts ensure files persist after container exits

## Usage

```bash
# Build with camera selection (incremental)
./build-container.sh

# Clean build from scratch
./build-container.sh cleanbuild

# Debug build (serial, verbose)
./build-container.sh dev

# Interactive shell
./build-container.sh shell

# Other commands
./build-container.sh info
./build-container.sh rebuild-image
```

## Container Image

Uses a prebuilt image from
[ghcr.io/themactep/thingino-builder-image](https://github.com/themactep/thingino-builder-image).
Pulled automatically on first run. For air-gapped builds, build locally from
the thingino-builder-image repo and set `CONTAINER_TAG=local`.

## Output Location

Built firmware images appear at:
```
./output/<branch>/<camera_name>/images/
├── thingino-<camera_name>.bin         # Full image
└── ...
```
