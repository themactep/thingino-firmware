# LightNVR Buildroot Package Changelog

## [Unreleased] - 2024-10-30

### Changed
- **BREAKING:** Web assets are now built during the build process instead of being copied from git
- Added `host-nodejs` as a build dependency
- Added `LIGHTNVR_BUILD_WEB_ASSETS` pre-build hook to build web assets with npm
- Web assets are built with `npm ci && npm run build` before CMake configuration

### Added
- Comprehensive README.md documenting the package structure and usage
- This CHANGELOG.md to track package changes
- Build hook to automatically build web assets from source

### Migration Notes

**For existing users:**

This change aligns with LightNVR v0.13.0+ which no longer checks web assets into git.

**What you need to do:**
1. Update your `lightnvr.mk` to the new version (already done in this directory)
2. Ensure your Buildroot configuration includes `host-nodejs`
3. Rebuild the package: `make lightnvr-dirclean && make lightnvr`

**What changed in the build process:**
- Before: `cp -r $(@D)/web/dist $(TARGET_DIR)/var/nvr/web`
- After: Build web assets first, then copy them

**Why this change:**
- Cleaner git repository (no binary assets)
- Always builds from source (more reliable)
- Consistent with LightNVR's new automated build process
- Prevents version mismatches between code and assets

### Technical Details

**New dependency:**
```makefile
LIGHTNVR_DEPENDENCIES = ... host-nodejs
```

**New build hook:**
```makefile
define LIGHTNVR_BUILD_WEB_ASSETS
    @echo "Building LightNVR web assets..."
    cd $(@D)/web && \
        npm ci --production=false && \
        npm run build
    @echo "Web assets built successfully"
endef

LIGHTNVR_PRE_BUILD_HOOKS += LIGHTNVR_BUILD_WEB_ASSETS
```

**Installation unchanged:**
```makefile
cp -r $(@D)/web/dist $(TARGET_DIR)/var/nvr/web
```

The installation step remains the same - we still copy from `web/dist`, but now that directory is built during the build process instead of being in git.

## [Previous] - Before 2024-10-30

### Initial Version
- Package definition for LightNVR
- Dependencies: thingino-ffmpeg, thingino-libcurl, sqlite
- CMake configuration with SOD and go2rtc support
- Installation of binary, web assets, config, and init script
- SOD shared libraries installation
- FFmpeg 7 compatibility patch

### Features
- Builds LightNVR from git (main branch or specific commit)
- Installs to standard paths (/usr/bin, /var/nvr, /etc/lightnvr)
- Includes S95lightnvr init script
- Supports optional mbedtls or wolfssl
- Enables SOD object detection with dynamic linking
- Configures go2rtc integration

