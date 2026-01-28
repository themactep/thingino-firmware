# Pre-Trigger Buffer - Buildroot Integration

## Overview

The pre-trigger buffer feature is now integrated into the thingino-firmware buildroot system as a configurable option.

## Configuration

### Using menuconfig

```bash
make menuconfig
```

Navigate to:
```
Package Selection for the target
  → Multimedia
    → prudynt-t streamer
      → [*] Enable pre-trigger buffer for motion events
```

### Smart Defaults

The configuration automatically sets sensible defaults based on SoC family:

- **T31** (64MB): **Enabled by default** ✓
- **T40** (128MB+): **Enabled by default** ✓  
- **T41** (128MB+): **Enabled by default** ✓
- **T20/T21** (32MB): **Disabled by default**
- **T10** (32MB): **Disabled by default**

### Manual Override in defconfig

For camera-specific configurations, add to your defconfig:

```makefile
# Enable prebuffer (override default)
BR2_PACKAGE_PRUDYNT_T_PREBUFFER=y

# Disable prebuffer (override default)
# BR2_PACKAGE_PRUDYNT_T_PREBUFFER is not set
```

## Build Integration

The buildroot package automatically passes the correct flag to the prudynt-t Makefile:

```makefile
# Enabled: make USE_PREBUFFER=1
# Disabled: make USE_PREBUFFER=0
```

No manual intervention required - it just works!

## Runtime Configuration

When prebuffer is compiled in (enabled), configure it in `/etc/prudynt.json`:

```json
{
  "recorder": {
    "prebuffer_enabled": true,
    "prebuffer_seconds": 3,
    "prebuffer_keyframe_only": false,
    "prebuffer_max_memory_mb": 2
  }
}
```

When prebuffer is compiled out (disabled), these configuration options are ignored.

## Memory Impact by Platform

### T31 (64MB RAM) - Default: ENABLED ✓
- **Available RAM**: ~40-45MB after kernel/system
- **Prudynt base**: ~10-15MB
- **Prebuffer cost**: ~2MB per channel (with defaults)
- **Remaining**: ~25-30MB headroom
- **Verdict**: Safe and recommended

### T40/T41 (128MB+ RAM) - Default: ENABLED ✓
- **Available RAM**: ~90-100MB after kernel/system
- **Prebuffer cost**: Negligible
- **Verdict**: Plenty of headroom

### T20/T21/T10 (32MB RAM) - Default: DISABLED
- **Available RAM**: ~15-20MB after kernel/system
- **Prudynt base**: ~10-15MB
- **Prebuffer cost**: Would consume most remaining RAM
- **Verdict**: Disable to preserve stability

## Build Verification

After building firmware, verify prebuffer status:

```bash
# Check if prebuffer is compiled in
nm output/target/usr/bin/prudynt | grep -i prebuffer

# If enabled, you'll see symbols like:
# PreTriggerBuffer::init
# PreTriggerBuffer::addFrame
# PreTriggerBuffer::getFrames

# If disabled, no prebuffer symbols
```

## Camera-Specific Overrides

To override defaults for specific camera models, edit:

```
configs/<camera>/<camera>.config
```

Example for a 32MB T31 variant:
```makefile
# Force disable prebuffer on this low-RAM T31
# BR2_PACKAGE_PRUDYNT_T_PREBUFFER is not set
```

Example for a 128MB T20 variant (rare):
```makefile
# Force enable prebuffer on this high-RAM T20
BR2_PACKAGE_PRUDYNT_T_PREBUFFER=y
```

## Migration Notes

### Existing Builds
- Rebuilding with the new package will apply smart defaults
- T31/T40/T41 builds will gain prebuffer automatically
- T20/T21 builds will compile without it (saves space)

### Existing Configurations
- If you have `prebuffer_enabled: true` in `/etc/prudynt.json`:
  - **With prebuffer compiled in**: Works as expected
  - **Without prebuffer compiled in**: Option ignored (no error)

### Firmware Size Impact
- **With prebuffer**: +3-4KB binary size
- **Without prebuffer**: Baseline size

## Troubleshooting

### "Out of Memory" on T31
If you enabled prebuffer and experience OOM:
1. Reduce `prebuffer_seconds` from 3 to 2
2. Enable `prebuffer_keyframe_only: true` (saves 70% RAM)
3. Reduce `prebuffer_max_memory_mb` from 2 to 1
4. As last resort: rebuild with `BR2_PACKAGE_PRUDYNT_T_PREBUFFER=n`

### Prebuffer Not Working
Check if it's compiled in:
```bash
# On camera
nm /usr/bin/prudynt | grep PreTriggerBuffer

# If no output, rebuild firmware with prebuffer enabled
```

### Build Errors
If the build fails with prebuffer-related errors:
1. Clean the prudynt-t package: `make prudynt-t-dirclean`
2. Rebuild: `make prudynt-t-rebuild`
3. If still fails, check buildroot version compatibility

## Developer Notes

The integration consists of:

1. **Config.in**: Adds `BR2_PACKAGE_PRUDYNT_T_PREBUFFER` option
2. **prudynt-t.mk**: Passes `USE_PREBUFFER=0/1` to Makefile
3. **Makefile**: Adds `-DPREBUFFER_ENABLED` when enabled
4. **Source code**: Wrapped with `#ifdef PREBUFFER_ENABLED`

The chain is fully automated - just select the option in menuconfig!
