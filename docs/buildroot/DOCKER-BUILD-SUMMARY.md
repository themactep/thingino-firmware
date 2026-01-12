# Docker Build System - Quick Reference

## Successfully Implemented Features

### 1. Interactive Camera Selection
- **fzf-based selection** with fuzzy matching (exact substring mode)
- Camera selection **persists** between builds (stored in `.camera-selection`)
- ANSI escape codes properly stripped from selection

### 2. Build Modes
- **Default (./docker-build.sh)**: Incremental parallel build - resumes from where it left off
- **Clean Build**: `./docker-build.sh clean` - Clean slate + parallel build
- **Dev Build**: `./docker-build.sh dev` - Serial build with V=1 verbose output (debugging)
- **Shell**: `./docker-build.sh shell` - Interactive container shell

### 3. Signal Handling
- **Ctrl-C properly stops builds** - traps SIGINT and cleans up container processes

### 4. Output Persistence
- Build artifacts saved to `output-stable/<camera>/images/` on host
- Volume mounts ensure files persist after container exits
- HOME override ensures output goes to workspace: `-e HOME=/home/builder/build`

### 5. Key Technical Fixes
- Fixed ANSI escape code pollution from fzf using `sed` stripping
- Fixed Ctrl-C handling with proper signal trapping and cleanup
- Fixed output directory location by overriding HOME in container
- Fixed locale warnings with proper locale generation in Dockerfile
- Used `pwd` instead of `$(CURDIR)` for symlink compatibility

## Usage

```bash
# Build with camera selection (incremental)
./docker-build.sh

# Clean build from scratch
./docker-build.sh clean

# Debug build (serial, verbose)
./docker-build.sh dev

# Interactive shell
./docker-build.sh shell

# Other commands
./docker-build.sh info
./docker-build.sh clean-docker
```

## Output Location

Built firmware images appear at:
```
./output-stable/<camera_name>/images/
├── thingino-<camera_name>.bin         # Full image
└── thingino-<camera_name>-update.bin  # Update image
```

