# daynightd - Automatic Day/Night Mode Switching Daemon

A lightweight, efficient daemon for automatic day/night mode switching on Thingino firmware, optimized for MIPS Ingenic XBurst embedded systems.

## Overview

`daynightd` continuously monitors scene brightness through ISP and automatically switches between day and night modes based on configurable thresholds. It's designed specifically for resource-constrained embedded IP cameras running Thingino firmware.

## Features

- **Thingino Integration**: Native integration with Thingino firmware tools and interfaces
- **Hysteresis Logic**: Prevents oscillation between modes with configurable thresholds
- **Resource Optimized**: Minimal CPU and memory footprint for embedded systems
- **Configurable Sampling**: Adjustable brightness sampling intervals and algorithms
- **Hardware Integration**: Uses Thingino scripts for IR cut filter and camera mode control
- **Signal Control**: Runtime mode switching via UNIX signals
- **Robust Operation**: Graceful error handling and recovery
- **Comprehensive Logging**: Syslog integration with configurable verbosity

## Architecture

The daemon implements a **standalone userspace process** approach, which provides the optimal balance of:

- ✅ **Resource efficiency** - Minimal memory (~100KB) and CPU usage
- ✅ **System stability** - Userspace crashes don't affect kernel
- ✅ **Maintainability** - Standard debugging tools and development practices
- ✅ **Flexibility** - Runtime configuration and signal-based control
- ✅ **Platform compatibility** - Native integration with Thingino firmware

### Thingino Integration

The daemon is specifically designed for Thingino firmware and uses:

- **ISP Integration**: Direct analysis of Ingenic ISP parameters from `/proc/jz/isp/isp-m0`
- **Minimal Dependencies**: Only essential Thingino scripts (`/sbin/daynight`)
- **Ultra-Efficient**: Optimized for minimal CPU and memory usage
- **Reliable Fallbacks**: Simple time-based detection when ISP unavailable

### Brightness Detection Methods

The daemon uses a minimal set of detection methods for optimal efficiency:

1. **ISP Parameters** (Primary): Direct analysis of Ingenic ISP data from `/proc/jz/isp/isp-m0`
   - Integration time ratio (exposure) - lower = brighter scene
   - Analog/digital gain levels - higher = darker scene
   - Current ISP mode (Day/Night) and brightness settings
2. **Thingino Scripts** (Fallback): Basic mode detection via `/usr/bin/daynight`
3. **Time-based Fallback**: System time heuristics as last resort
4. **Smoothing Algorithm**: Rolling average to reduce noise and false triggers

## Quick Start

### Building

```bash
# For MIPS target (cross-compilation)
make

# For development/testing (native compilation)
make dev
```

### Installation

```bash
# Install to target system
make install

# Or specify custom installation directory
make install DESTDIR=/path/to/rootfs
```

### Configuration

```bash
# Copy example configuration
cp daynightd.json.example /etc/daynightd.json

# Edit thresholds for your environment
vi /etc/daynightd.conf
```

### Running

```bash
# Start daemon
/etc/init.d/daynightd start

# Check status
/etc/init.d/daynightd status

# Stop daemon
/etc/init.d/daynightd stop
```

## Configuration

The daemon uses **structured JSON configuration format**.

### JSON Configuration

```json
{
  "device_path": "/dev/isp-m0",
  "brightness_thresholds": {
    "threshold_low": 25.0,
    "threshold_high": 75.0,
    "hysteresis_factor": 0.1
  },
  "timing": {
    "sample_interval_ms": 500,
    "transition_delay_s": 5
  },
  "hardware": {
    "enable_ir_cut": true
  },
  "system": {
    "enable_syslog": true,
    "daemon_mode": true,
    "debug_level": 0,
    "pid_file": "/var/run/daynightd.pid"
  }
}
```

### Configuration Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `device_path` | string | `/dev/isp-m0` | ISP device path for Thingino |
| `threshold_low` | float | 25.0 | Switch to night mode below this brightness (%) |
| `threshold_high` | float | 75.0 | Switch to day mode above this brightness (%) |
| `sample_interval_ms` | int | 500 | Brightness check interval (100-60000ms) |
| `transition_delay_s` | int | 5 | Minimum time between mode changes (1-300s) |
| `hysteresis_factor` | float | 0.1 | Prevents oscillation (0.0-0.5) |
| `enable_ir_cut` | bool | true | Control IR cut filter via scripts |
| `enable_syslog` | bool | true | Log to system syslog |
| `daemon_mode` | bool | true | Run as background daemon |
| `debug_level` | int | 0 | Verbosity level (0=normal, 1+=debug) |
| `pid_file` | string | `/run/daynightd.pid` | PID file location |

## Signal Control

The daemon responds to UNIX signals for runtime control:

```bash
# Force day mode
kill -USR1 $(cat /var/run/daynightd.pid)

# Force night mode
kill -USR2 $(cat /var/run/daynightd.pid)

# Reload configuration
kill -HUP $(cat /var/run/daynightd.pid)

# Graceful shutdown
kill -TERM $(cat /var/run/daynightd.pid)
```

## Platform Requirements

### Hardware
- MIPS Ingenic XBurst processor (T20, T21, T23, T30, T31 series)
- V4L2-compatible camera sensor
- 8-32MB flash storage
- Minimal RAM requirements (~100KB runtime)

### Software
- Linux kernel 3.10+ with V4L2 support
- Thingino firmware
- Standard C library (uClibc/musl)

### Supported Pixel Formats
- YUV formats: YUYV, UYVY (preferred for efficiency)
- RGB formats: RGB24, BGR24
- Extensible architecture for additional formats

## Performance Characteristics

### Resource Usage
- **Memory**: ~50-100KB RAM
- **CPU**: <1% on T31 @ 1GHz with 1-second sampling
- **Storage**: ~50KB binary size (stripped)

### Timing
- **Startup**: <100ms initialization
- **Response**: Configurable 100ms - 60s sampling intervals
- **Transition**: 1-300s configurable delay between mode changes

## Troubleshooting

### Common Issues

**Brightness detection not working:**
```bash
# Run in foreground with debug
daynightd -f -v -v

# Check supported pixel formats
v4l2-ctl --device=/dev/video0 --list-formats
```

**Mode switching not occurring:**
```bash
# Check thresholds in configuration
grep threshold /etc/daynightd.conf

# Monitor brightness values
tail -f /var/log/messages | grep daynightd
```

### Debug Mode

```bash
# Run in foreground with maximum verbosity
daynightd -f -v -v -v
```

## Integration with Thingino

### Build System Integration

Add to Thingino package configuration:

```makefile
# package/daynightd/daynightd.mk
DAYNIGHTD_VERSION = 1.0.0
DAYNIGHTD_SITE = $(TOPDIR)/package/daynightd/src
DAYNIGHTD_SITE_METHOD = local

define DAYNIGHTD_BUILD_CMDS
    $(MAKE) CC="$(TARGET_CC)" CFLAGS="$(TARGET_CFLAGS)" -C $(@D)
endef

define DAYNIGHTD_INSTALL_TARGET_CMDS
    $(INSTALL) -D -m 755 $(@D)/daynightd $(TARGET_DIR)/usr/bin/daynightd
    $(INSTALL) -D -m 644 $(@D)/daynightd.conf.example $(TARGET_DIR)/etc/daynightd.conf
    $(INSTALL) -D -m 755 $(@D)/init.d/daynightd $(TARGET_DIR)/etc/init.d/daynightd
endef

$(eval $(generic-package))
```

### Startup Integration

The daemon integrates with standard init systems and can be started automatically at boot.

## Development

### Building for Development

```bash
# Native build for testing
make dev

# Run with debug output
./daynightd -f -v -v
```

### Testing

```bash
# Test configuration loading
./daynightd -c daynightd.conf.example -f -v

# Test signal handling
./daynightd -f &
kill -USR1 $!  # Force day mode
kill -USR2 $!  # Force night mode
kill -TERM $!  # Shutdown
```

## License

This project is licensed under the GNU General Public License v2.0 - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please ensure:

1. Code follows embedded systems best practices
2. Resource usage remains minimal
3. Compatibility with MIPS architecture is maintained
4. Changes are tested on actual hardware when possible

## Support

For issues and questions:
- Thingino Discord: https://discord.gg/xDmqS944zr
- Thingino Telegram: https://t.me/thingino
- GitHub Issues: https://github.com/themactep/thingino-firmware/issues
