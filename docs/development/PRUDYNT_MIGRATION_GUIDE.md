# Prudynt Configuration Migration Guide

## Overview

This document describes the migration from `prudyntcfg` to `jct` (JSON Configuration Tool) in the thingino project. The prudynt streamer configuration has been refactored from a custom config format to pure JSON, requiring updates to all tools and scripts that interact with the configuration.

## Key Changes

### Configuration File Format
- **Old**: `/etc/prudynt.cfg` (custom libconfig format)
- **New**: `/etc/prudynt.json` (pure JSON format)

### Command Line Tool
- **Old**: `prudyntcfg` (AWK-based tool)
- **New**: `jct` (JSON Configuration Tool)

## Command Syntax Changes

### Reading Configuration Values

**Old syntax:**
```bash
prudyntcfg get section.key
```

**New syntax:**
```bash
jct /etc/prudynt.json get section.key
```

### Setting Configuration Values

**Old syntax:**
```bash
prudyntcfg set section.key "value"
```

**New syntax:**
```bash
jct /etc/prudynt.json set section.key value
```

### Examples

| Operation | Old Command | New Command |
|-----------|-------------|-------------|
| Get RTSP port | `prudyntcfg get rtsp.port` | `jct /etc/prudynt.json get rtsp.port` |
| Set RTSP password | `prudyntcfg set rtsp.password "mypass"` | `jct /etc/prudynt.json set rtsp.password mypass` |
| Get stream endpoint | `prudyntcfg get stream0.rtsp_endpoint` | `jct /etc/prudynt.json get stream0.rtsp_endpoint` |
| Check motion enabled | `prudyntcfg get motion.enabled` | `jct /etc/prudynt.json get motion.enabled` |

## Files Updated

### Shell Scripts
- `package/prudynt-t/files/S96vbuffer`
- `package/thingino-webui/files/www/x/config-rtsp.cgi`
- `package/thingino-webui/files/www/x/_common.cgi`

### Lua Scripts
- `package/thingino-webui-lua/files/www/lua/main.lua`
- `package/thingino-webui-lua/files/www/lua/lib/utils.lua`

### Build System
- `package/prudynt-t/prudynt-t.mk`
- `package/prudynt-t/Config.in`

## Configuration Format Migration

### Old Format Example (prudynt.cfg)
```
rtsp = {
    port = 554;
    username = "thingino";
    password = "thingino";
};

stream0 = {
    rtsp_endpoint = "ch0";
    width = 1920;
    height = 1080;
};
```

### New Format Example (prudynt.json)
```json
{
  "rtsp": {
    "port": "554",
    "username": "thingino",
    "password": "thingino"
  },
  "stream0": {
    "rtsp_endpoint": "ch0",
    "width": 1920,
    "height": 1080
  }
}
```

## Migration Steps for Existing Installations

1. **Convert existing configuration:**
   ```bash
   # Use the provided migration script
   /usr/bin/cfg-to-json.sh /etc/prudynt.cfg /etc/prudynt.json
   ```

2. **Validate JSON format:**
   ```bash
   jct /etc/prudynt.json print
   ```

3. **Test configuration access:**
   ```bash
   jct /etc/prudynt.json get rtsp.port
   ```

## Benefits of the Migration

1. **Standard Format**: JSON is widely supported and standardized
2. **Better Tooling**: JSON validation, formatting, and editing tools
3. **Cleaner Config**: No comments in config files for pure data format
4. **Reuses Existing Library**: Uses json-c library already present in firmware
5. **Smaller Binary**: No additional library compilation needed

## Troubleshooting

### Common Issues

1. **jct command not found**
   - Ensure `thingino-jct` package is installed and selected in buildroot config

2. **Configuration file not found**
   - Check if `/etc/prudynt.json` exists
   - Migrate from old format using `cfg-to-json.sh`

3. **Invalid JSON format**
   - Validate JSON using `jct /etc/prudynt.json print`
   - Check for syntax errors (missing commas, quotes, etc.)

### Testing the Migration

Use the provided test script to verify the migration:
```bash
./test_prudynt_migration.sh
```

## Backward Compatibility

The old `prudyntcfg` tool is no longer installed. All references have been updated to use `jct`. If you have custom scripts that use `prudyntcfg`, they need to be updated to use the new `jct` syntax.

## Dependencies

The prudynt-t package now depends on:
- `thingino-jct` (JSON Configuration Tool)
- `json-c` (JSON parsing library)

The old dependency on `libconfig` has been removed.
