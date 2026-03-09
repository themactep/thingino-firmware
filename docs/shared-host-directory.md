# Shared Host Directory - Avoiding Host Package Rebuilds

## Problem

Buildroot rebuilds all host packages (like host-gcc, host-cmake, etc.) for every camera configuration, wasting significant time.

## Solution

Use a shared host directory that is reused across all builds. This is now **automatically handled** by the build system with **version tracking**!

## How It Works

The Makefile now:
1. **Automatically detects** if a shared host directory exists and is populated
2. **Tracks Buildroot version** to detect when host packages need rebuilding
3. **Warns you** if there's a version mismatch
4. **Safely falls back** to per-build host if needed

No manual configuration needed!

## Quick Start

```bash
# 1. Build any camera normally
make CAMERA=your_camera

# 2. Populate the shared host directory (one-time)
make CAMERA=your_camera populate-shared-host

# 3. Check status anytime
make CAMERA=your_camera check-shared-host

# 4. All future builds automatically use shared host!
make CAMERA=another_camera  # Reuses host packages
```

## Version Tracking

### What Gets Tracked

When you run `make populate-shared-host`, it saves:
- **Buildroot version** (from `.git/HEAD`) in `~/.buildroot-host-shared/.buildroot-version`
- **Timestamp** in `~/.buildroot-host-shared/.timestamp`

### Automatic Version Checking

Every build automatically checks if the shared host directory was built with the same Buildroot version:

```
✓ Version matches current Buildroot
```

Or if there's a mismatch:

```
⚠️  WARNING: VERSION MISMATCH!
  Shared:  abc123def
  Current: xyz789ghi

Consider rebuilding shared host directory:
  rm -rf ~/buildroot-host-shared
  make CAMERA=any_camera
  make populate-shared-host

Continuing with existing shared host (may cause issues)...
```

The build **pauses for 3 seconds** to show the warning, then continues. This gives you time to notice the issue but doesn't break your build.

## When to Rebuild Shared Host

You should rebuild the shared host directory when:

1. **Buildroot submodule updated** (after `git pull` or `make update`)
2. **Host package versions changed** in buildroot
3. **Build failures** related to host tools
4. **Version mismatch warnings** appear

```bash
# Quick rebuild
rm -rf ~/buildroot-host-shared
make CAMERA=any_camera
make CAMERA=any_camera populate-shared-host
```

## Commands

### `make check-shared-host`

Check the status of your shared host directory:

```bash
make CAMERA=any_camera check-shared-host
```

**Output examples:**

**Not created yet:**
```
Status: Shared host directory does NOT exist
Location: /home/user/buildroot-host-shared

To create it:
  1. make CAMERA=any_camera
  2. make populate-shared-host
```

**Populated and ready:**
```
Status: Shared host directory is POPULATED and ready
Location: /home/user/buildroot-host-shared
Buildroot version: ref: refs/heads/master
✓ Version matches current Buildroot
Last updated: 2026-01-22 04:34:42

Directory size: 588M
```

**Version mismatch:**
```
Status: Shared host directory is POPULATED and ready
Location: /home/user/buildroot-host-shared
Buildroot version: abc123def

⚠️  WARNING: VERSION MISMATCH!
  Shared:  abc123def
  Current: xyz789ghi

Recommendation: Rebuild shared host directory
  rm -rf /home/user/buildroot-host-shared
  make CAMERA=any_camera
  make populate-shared-host
```

### `make populate-shared-host`

Copies the current build's host directory to the shared location with version tracking.

**Requirements:**
- Must have completed at least one successful build
- The current OUTPUT_DIR must contain a populated `host/` directory

**What it does:**
```bash
rsync -a --delete ~/output-stable/your_camera/host/ ~/buildroot-host-shared/
# Saves Buildroot version
# Saves timestamp
```

**Output:**
```
Copying host directory to /home/user/buildroot-host-shared...
Done! Shared host directory populated.
Buildroot version: ref: refs/heads/master
Timestamp: 2026-01-22 04:34:42
Future builds will automatically use this shared directory.
```

## Automatic Detection During Build

When you run `make defconfig`, the system:

1. Checks if `~/buildroot-host-shared` exists
2. Checks if it has `bin/` and `lib/` directories
3. Compares Buildroot versions
4. Shows appropriate message:
   - `* Using shared host directory: /home/user/buildroot-host-shared`
   - `* Shared host directory not found or empty, using default per-build host`

## Benefits

- **Fully automatic**: No config changes needed
- **Version safe**: Warns about mismatches
- **Faster rebuilds**: Host packages built only once (when versions match)
- **Disk space**: Shared across all camera configs
- **Transparent**: Clear status messages

## Important Notes

### Compatibility

- ✅ Safe to share across different camera models
- ✅ Safe to share across different OUTPUT_DIR locations
- ✅ Auto-detects version mismatches
- ⚠️ Must use same toolchain version (gcc 13.3, musl, etc.)
- ⚠️ Must use same architecture (mipsel for Ingenic)

### Directory Structure

```
~/buildroot-host-shared/
├── .buildroot-version  # Buildroot git HEAD reference
├── .timestamp          # When last populated
├── bin/                # Cross-compiler and host tools
├── include/            # Host headers
├── lib/                # Host libraries
├── mipsel-buildroot-linux-musl/  # Target sysroot
└── share/              # Documentation, cmake files, etc.
```

## Workflow Examples

### After Buildroot Update

```bash
# Update buildroot submodule
make update

# Check if shared host needs rebuilding
make CAMERA=any_camera check-shared-host

# If version mismatch, rebuild
rm -rf ~/buildroot-host-shared
make CAMERA=any_camera
make CAMERA=any_camera populate-shared-host
```

### Building Multiple Cameras

```bash
# First camera
make CAMERA=camera1
make CAMERA=camera1 populate-shared-host

# Subsequent cameras (reuse host packages)
make CAMERA=camera2  # Fast!
make CAMERA=camera3  # Fast!
make CAMERA=camera4  # Fast!
```

### Checking Before Long Build Session

```bash
# Verify shared host is ready and up-to-date
make CAMERA=any_camera check-shared-host

# If all good, start building
make CAMERA=camera1
make CAMERA=camera2
# etc.
```

## Troubleshooting

### Build fails with "host tool not found"

The shared host directory might be incomplete or corrupted:
```bash
rm -rf ~/buildroot-host-shared
make CAMERA=your_camera
make CAMERA=your_camera populate-shared-host
```

### Version mismatch warnings

After updating buildroot or pulling changes:
```bash
# Check status
make CAMERA=any_camera check-shared-host

# Rebuild if needed
rm -rf ~/buildroot-host-shared
make CAMERA=any_camera
make CAMERA=any_camera populate-shared-host
```

### "Inconsistent toolchain" errors

Different cameras may need different toolchains. Either:
1. Use separate shared directories per toolchain
2. Clear and rebuild the shared directory

### Disable shared host temporarily

```bash
rm -rf ~/buildroot-host-shared
# Next build will use default per-build host
```

### Check current configuration

```bash
grep BR2_HOST_DIR ~/output-stable/your_camera/.config
```

## Advanced Usage

### Per-Branch Shared Directories

For different git branches with different Buildroot versions:

```bash
# Modify the Makefile to use branch-specific directories
SHARED_HOST="$(HOME)/buildroot-host-$(GIT_BRANCH)"
```

Then each branch gets its own shared directory:
- `~/buildroot-host-master`
- `~/buildroot-host-stable`
- `~/buildroot-host-develop`

## See Also

- [Buildroot Manual - Using Buildroot Toolchain](buildroot/manual.text)
- Search for "SDK" and "BR2_HOST_DIR" in manual
- `make sdk` - Alternative method using relocatable SDK
