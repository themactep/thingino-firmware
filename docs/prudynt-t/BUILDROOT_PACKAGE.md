# Prudynt-T Buildroot Package Updates

This directory contains the updated buildroot package files for prudynt-t with JSON configuration support.

## Changes Made

### Dependencies
- **Removed**: `libconfig` dependency
- **Added**: `json-c` dependency (reuses existing firmware library)

### Configuration Format
- **Old**: libconfig format (`.cfg` files)
- **New**: Pure JSON format (`.json` files)

### Files Updated

#### Config.in
- Replaced `BR2_PACKAGE_LIBCONFIG` with `BR2_PACKAGE_JSON_C`
- Removed C++11/GCC requirements (json-c is a C library)
- Updated help text to mention JSON configuration

#### prudynt-t.mk
- Updated `PRUDYNT_T_DEPENDENCIES` to use `json-c`
- Modified install commands to handle `.json` files instead of `.cfg`
- Simplified configuration processing (no more complex awk scripts)
- Updated low-memory device buffer adjustment for JSON format

#### Migration Tools
- Added `cfg-to-json.sh` script for converting existing configurations

## Installation

1. Copy these files to your thingino buildroot package directory:
   ```bash
   cp -r buildroot-package/* /path/to/thingino/package/prudynt-t/
   ```

2. Rebuild the package:
   ```bash
   make prudynt-t-rebuild
   ```

## Configuration Migration

For existing installations with `.cfg` files:

1. Use the migration script:
   ```bash
   ./files/cfg-to-json.sh /etc/prudynt.cfg /etc/prudynt.json
   ```

2. Validate the JSON:
   ```bash
   jq . /etc/prudynt.json
   # OR use the thingino JSON config tool
   jct /etc/prudynt.json print
   ```

3. Review and adjust manually if needed

## JSON Configuration Management

The thingino firmware includes `jct` (JSON Config Tool) for easy configuration management:

```bash
# Get a configuration value
jct /etc/prudynt.json get motion.enabled

# Set a configuration value
jct /etc/prudynt.json set motion.enabled true

# Print entire configuration
jct /etc/prudynt.json print
```

## Benefits

- **Standard Format**: JSON is widely supported and standardized
- **Better Tooling**: JSON validation, formatting, and editing tools
- **Cleaner Config**: No comments in config files for pure data format
- **Reuses Existing Library**: Uses json-c library already present in firmware
- **Smaller Binary**: No additional library compilation needed

## Compatibility

- Uses standard C library (json-c) - no special compiler requirements
- Reuses existing libjson-c.so library in firmware
- All existing prudynt-t functionality remains unchanged
- Only configuration file format changes
