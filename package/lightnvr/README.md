# LightNVR Buildroot Package

This directory contains the Buildroot package definition for LightNVR, used by thinginfo-firmware.

## Overview

This package builds and installs LightNVR on embedded devices using Buildroot. It handles:
- Building the C/C++ application with CMake
- Building web assets with Node.js and Vite
- Installing the application, web interface, and configuration files
- Setting up the init script for automatic startup

## Recent Changes (v0.13.0+)

**Important:** Starting with LightNVR v0.13.0, web assets (`web/dist/`) are **no longer checked into git**. They are now built during the build process.

### What Changed

**Before:**
- Web assets were pre-built and checked into the git repository
- Buildroot simply copied `web/dist/` from the source tree
- No Node.js dependency needed

**After:**
- Web assets are built during the Buildroot build process
- Requires `host-nodejs` as a build dependency
- Uses `npm ci && npm run build` to build assets
- Cleaner git repository, always builds from source

### Migration

If you're updating from an older version of this package:

1. **Update `lightnvr.mk`** - Already done in this directory
2. **Ensure `host-nodejs` is available** in your Buildroot configuration
3. **Rebuild the package** - Web assets will be built automatically

## Package Structure

```
lightnvr-buildroot/
├── lightnvr.mk                    # Main package definition
├── Config.in                      # Buildroot configuration
├── files/
│   └── S95lightnvr               # Init script
├── 0001-fix-ffmpeg7-*.patch      # FFmpeg compatibility patch
└── README.md                      # This file
```

## Dependencies

### Runtime Dependencies
- `thingino-ffmpeg` - Video processing
- `thingino-libcurl` - HTTP client
- `sqlite` - Database
- `mbedtls` or `thingino-wolfssl` - TLS/SSL (optional)

### Build Dependencies
- `host-nodejs` - **NEW** - Required to build web assets
- CMake (provided by Buildroot)
- Standard build tools (gcc, make, etc.)

## Build Process

The package follows this build sequence:

1. **Download source** from GitHub (main branch or specific commit)
2. **Build web assets** (PRE_BUILD_HOOKS):
   ```bash
   cd web/
   npm ci --production=false
   npm run build
   ```
3. **Configure with CMake**:
   - Enable SOD (object detection)
   - Enable go2rtc integration
   - Set paths and options
4. **Build C/C++ code** with CMake
5. **Install to target**:
   - Binary: `/usr/bin/lightnvr`
   - Web assets: `/var/nvr/web/`
   - Config: `/etc/lightnvr/lightnvr.ini`
   - Init script: `/etc/init.d/S95lightnvr`
   - SOD libraries: `/usr/lib/libsod.so*`

## Configuration Options

### CMake Options

The package configures LightNVR with:

```makefile
LIGHTNVR_CONF_OPTS = \
    -DENABLE_SOD=ON \
    -DSOD_DYNAMIC_LINK=ON \
    -DENABLE_GO2RTC=ON \
    -DGO2RTC_BINARY_PATH=/bin/go2rtc \
    -DGO2RTC_CONFIG_DIR=/etc/lightnvr/go2rtc \
    -DGO2RTC_API_PORT=1984
```

### Version Pinning

The package uses a specific git commit by default:

```makefile
LIGHTNVR_VERSION = 6e209ff87757c8f4c70a8258b7452a8d950bfabd
```

To update to a newer version:
1. Find the commit hash from https://github.com/opensensor/lightNVR
2. Update `LIGHTNVR_VERSION` in `lightnvr.mk`
3. Rebuild the package

To use the latest main branch:
```makefile
LIGHTNVR_VERSION = main
```

## Installation Paths

| Component | Target Path |
|-----------|-------------|
| Binary | `/usr/bin/lightnvr` |
| Web assets | `/var/nvr/web/` |
| Configuration | `/etc/lightnvr/lightnvr.ini` |
| go2rtc config | `/etc/lightnvr/go2rtc/` |
| Init script | `/etc/init.d/S95lightnvr` |
| SOD libraries | `/usr/lib/libsod.so*` |
| Data directory | `/var/nvr/` |

## Usage in Buildroot

### Adding to Your Buildroot Tree

1. Copy this directory to your Buildroot external tree:
   ```bash
   cp -r lightnvr-buildroot/ /path/to/buildroot/package/lightnvr/
   ```

2. Add to your package menu (e.g., `package/Config.in`):
   ```
   source "package/lightnvr/Config.in"
   ```

3. Enable in menuconfig:
   ```bash
   make menuconfig
   # Navigate to: Target packages -> Networking applications -> lightnvr
   ```

4. Build:
   ```bash
   make lightnvr
   ```

### Rebuilding After Changes

```bash
# Clean and rebuild
make lightnvr-dirclean
make lightnvr

# Or rebuild everything
make clean
make
```

## Troubleshooting

### "npm: command not found"

**Problem:** Node.js is not available during build.

**Solution:** Ensure `host-nodejs` is in the dependencies:
```makefile
LIGHTNVR_DEPENDENCIES = ... host-nodejs
```

### "web/dist not found"

**Problem:** Web assets weren't built before installation.

**Solution:** This should not happen with the updated package. If it does:
1. Check that `LIGHTNVR_PRE_BUILD_HOOKS` is set correctly
2. Verify the build hook is executing (check build logs)
3. Ensure `npm ci && npm run build` completes successfully

### "libsod.so not found"

**Problem:** SOD libraries weren't installed.

**Solution:** Check that `LIGHTNVR_INSTALL_LIBSOD` is called in `LIGHTNVR_INSTALL_TARGET_CMDS`.

### Build fails with Node.js errors

**Problem:** Node.js version incompatibility or network issues.

**Solutions:**
- Ensure Buildroot has a recent `host-nodejs` package (Node.js 18+ recommended)
- Check network connectivity for npm package downloads
- Try clearing npm cache: `rm -rf $(@D)/web/node_modules`

### Version mismatch

**Problem:** Web interface shows different version than binary.

**Solution:** This should not happen anymore with the automated build process. If it does:
1. Verify you're using the updated `lightnvr.mk` with web asset building
2. Check that the version in `CMakeLists.txt` matches `web/package.json`
3. Rebuild from clean state: `make lightnvr-dirclean && make lightnvr`

## Testing

### Test the Package Build

```bash
# In your Buildroot directory
make lightnvr-dirclean
make lightnvr V=1  # Verbose output

# Check installed files
ls -la output/target/usr/bin/lightnvr
ls -la output/target/var/nvr/web/
ls -la output/target/etc/lightnvr/
```

### Test on Target Device

```bash
# After flashing the firmware
ssh root@device-ip

# Check service status
/etc/init.d/S95lightnvr status

# Start service
/etc/init.d/S95lightnvr start

# Check web interface
curl http://localhost:8080

# Check version
lightnvr --version
```

## Integration with thinginfo-firmware

This package is designed for use with thinginfo-firmware. To integrate:

1. **Add to external tree:**
   ```bash
   cd thinginfo-firmware
   cp -r /path/to/lightnvr-buildroot package/lightnvr/
   ```

2. **Update package list:**
   Add to `package/Config.in` or your external tree's config.

3. **Enable in defconfig:**
   ```
   BR2_PACKAGE_LIGHTNVR=y
   ```

4. **Build firmware:**
   ```bash
   make
   ```

## Maintenance

### Updating to New LightNVR Version

1. **Check for breaking changes** in LightNVR release notes
2. **Update version** in `lightnvr.mk`:
   ```makefile
   LIGHTNVR_VERSION = <new-commit-hash>
   ```
3. **Test build** in Buildroot
4. **Update patches** if needed (check `0001-*.patch` files)
5. **Test on target** device

### Updating Dependencies

If LightNVR adds new dependencies:

1. Add to `LIGHTNVR_DEPENDENCIES` in `lightnvr.mk`
2. Add to `Config.in` if user-selectable
3. Update CMake options if needed

## License

This package definition follows the same license as LightNVR (GPL v3.0).

## Support

For issues with:
- **LightNVR itself**: https://github.com/opensensor/lightNVR/issues
- **Buildroot package**: Open an issue in the thinginfo-firmware repository
- **Build process**: Check the troubleshooting section above

## See Also

- [LightNVR Release Process](../docs/RELEASE_PROCESS.md)
- [LightNVR Build Instructions](../docs/BUILD.md)
- [Buildroot Manual](https://buildroot.org/downloads/manual/manual.html)

