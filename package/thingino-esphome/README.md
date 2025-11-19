# Thingino ESPHome Package

ESPHome Linux integration for Thingino cameras, providing native Home Assistant integration via the ESPHome Native API protocol.

## Overview

This package integrates [esphome-linux](https://github.com/yinzara/esphome-linux) into Thingino firmware, enabling Thingino cameras to function as ESPHome devices with full Home Assistant auto-discovery and integration.

## Features

- **ESPHome Native API** - Full protocol implementation over TCP port 6053
- **Bluetooth Proxy** - BLE device scanning and forwarding to Home Assistant
- **Auto-Discovery** - mDNS service advertisement for automatic Home Assistant discovery
- **Plugin Architecture** - Extensible system for custom Thingino-specific features
- **Lightweight** - Optimized for embedded systems with minimal resource usage

## Architecture

```
┌─────────────────────────────────────────┐
│         Home Assistant                   │
│    (ESPHome Integration)                 │
└─────────────┬───────────────────────────┘
              │ ESPHome Native API (TCP 6053)
              │
┌─────────────▼───────────────────────────┐
│      esphome-linux Service               │
│  ┌────────────────────────────────────┐ │
│  │    ESPHome API Server Core         │ │
│  │  - Protocol handling               │ │
│  │  - Device info                     │ │
│  │  - mDNS advertisement              │ │
│  └────────────┬───────────────────────┘ │
│               │                          │
│  ┌────────────▼───────────────────────┐ │
│  │       Plugin Manager               │ │
│  │  - Load/unload plugins             │ │
│  │  - Route messages to plugins       │ │
│  └────────────┬───────────────────────┘ │
│               │                          │
│  ┌────────────▼───────────────────────┐ │
│  │         Plugins                    │ │
│  │  ┌──────────────────────────────┐ │ │
│  │  │  Bluetooth Proxy             │ │ │
│  │  │  (D-Bus → BlueZ)             │ │ │
│  │  └──────────────────────────────┘ │ │
│  │  ┌──────────────────────────────┐ │ │
│  │  │  Thingino Media Player       │ │ │
│  │  │                              │ │ │
│  │  └──────────────────────────────┘ │ │
│  │  ┌──────────────────────────────┐ │ │
│  │  │  Thingino Motion Detection   │ │ │
│  │  │  (Future)                    │ │ │
│  │  └──────────────────────────────┘ │ │
│  └──────────────────────────────────┘ │
└─────────────┬───────────────────────────┘
              │
┌─────────────▼───────────────────────────┐
│         Thingino System                  │
│  - BlueZ (Bluetooth)                     │
│  - D-Bus (IPC)                           │
│  - mdnsd (Service Discovery)             │
│  - prudynt (Video Streaming)             │
│  - GPIO/Hardware Control                 │
└──────────────────────────────────────────┘
```

## Package Structure

```
package/thingino-esphome/
├── Config.in                    # Buildroot configuration
├── thingino-esphome.mk         # Buildroot package makefile
├── README.md                   # This file
├── files/                      # Runtime files
│   └── S60esphome-service      # Init script
└── plugins/                    # Thingino-specific plugins
    ├── README.md               # Plugin development guide
    └── [future plugins]        # Custom Thingino integrations
```

## Build Configuration

The package uses the [meson build system](https://mesonbuild.com/) and integrates with Buildroot via the `meson-package` infrastructure.

### Dependencies

Automatically selected when package is enabled:
- **dbus** - D-Bus message bus
- **libglib2** - GLib library
- **bluez5_utils** - BlueZ Bluetooth stack

Build-time dependencies:
- **host-meson** - Meson build system
- **host-pkgconf** - pkg-config tool

### Enabling the Package

Add to your camera defconfig:
```bash
# Include bluetooth fragment for all dependencies
FRAG: ... bluetooth ...

# Or manually enable
BR2_PACKAGE_THINGINO_ESPHOME=y
```

The `bluetooth` fragment automatically provides:
- `BR2_PACKAGE_BLUEZ5_UTILS=y`
- `BR2_PACKAGE_DBUS=y`
- `BR2_PACKAGE_LIBGLIB2=y`

### Build Options

Configure in `thingino-esphome.mk`:
```makefile
THINGINO_ESPHOME_CONF_OPTS = \
    -Denable_bluetooth_proxy=true \    # Enable/disable Bluetooth Proxy
    -Denable_plugins=true               # Enable/disable plugin system
```

## Runtime Configuration

### Service Management

The service is managed via the init script:

```bash
# Start service
/etc/init.d/S60esphome-service start

# Stop service
/etc/init.d/S60esphome-service stop

# Restart service
/etc/init.d/S60esphome-service restart

# Check status
/etc/init.d/S60esphome-service status
```

### mDNS Service Discovery

The init script automatically generates an mDNS service file at `/etc/mdns.d/esphome.service`:

```
name <hostname>
type _esphomelib._tcp
port 6053
txt version=2025.1.0
txt mac=<MAC_ADDRESS>
txt platform=thingino
txt board=ingenic_mips
txt network=ethernet
txt friendly_name=<hostname>
```

This allows Home Assistant to automatically discover the device.

### Bluetooth Setup

The service requires a working Bluetooth adapter (hci0):

1. Ensure Bluetooth module is loaded (ATBM6031x, SSV6158, etc.)
2. BlueZ service should be running
3. Init script will attempt to bring up hci0 if down

Check Bluetooth status:
```bash
hciconfig hci0
```

## Home Assistant Integration

### Automatic Discovery

1. Ensure mDNS is working on your network
2. Service should appear in Home Assistant's ESPHome integration
3. Add device through Home Assistant UI

### Manual Configuration

If auto-discovery doesn't work:

1. Go to Settings → Devices & Services → Add Integration
2. Select "ESPHome"
3. Enter camera IP address and port 6053
4. No encryption key needed (disable encryption in Home Assistant)

### Available Features

Currently supported:
- **Bluetooth Proxy** - BLE device scanning for Home Assistant

Planned plugins:
- **Camera Control** - Pan/Tilt, IR control, day/night mode
- **Motion Detection** - Forward motion events to Home Assistant
- **Video Streaming** - Integration with prudynt for live video
- **Audio** - Two-way audio support
- **Sensors** - Temperature, uptime, network stats

## Plugin Development

See [plugins/README.md](plugins/README.md) for detailed plugin development guide.

### Quick Start

Create a new plugin:
```bash
mkdir -p package/thingino-esphome/plugins/my_plugin
```

Implement plugin interface in `my_plugin.c`:
```c
#include "esphome_plugin.h"

bool plugin_init(void) {
    // Initialize your plugin
    return true;
}

void plugin_cleanup(void) {
    // Clean up resources
}

bool plugin_handle_message(const uint8_t *data, size_t len) {
    // Handle ESPHome messages
    return true;
}

ESPHOME_PLUGIN_EXPORT(
    .name = "my_plugin",
    .version = "1.0.0",
    .init = plugin_init,
    .cleanup = plugin_cleanup,
    .handle_message = plugin_handle_message
);
```

Rebuild:
```bash
make rebuild-thingino-esphome
```

## Troubleshooting

### Service won't start

Check logs:
```bash
logread | grep esphome
```

Common issues:
- Bluetooth adapter not found (check `hciconfig`)
- D-Bus not running (check `/var/run/dbus/system_bus_socket`)
- Port 6053 already in use

### Not discoverable in Home Assistant

1. Check mDNS service:
   ```bash
   cat /etc/mdns.d/esphome.service
   ps | grep mdnsd
   ```

2. Test mDNS resolution from another device:
   ```bash
   avahi-browse -r _esphomelib._tcp
   ```

3. Manually add device using IP address

### Bluetooth devices not appearing

1. Check BlueZ status:
   ```bash
   hciconfig hci0
   bluetoothctl
   ```

2. Test BLE scanning:
   ```bash
   hcitool lescan
   ```

3. Check D-Bus connection:
   ```bash
   dbus-send --system --dest=org.bluez --print-reply / org.freedesktop.DBus.Introspectable.Introspect
   ```

## Development

### Local Testing

Build and test on device:
```bash
# Build package
make rebuild-thingino-esphome

# Flash to device
make upgrade_ota CAMERA_IP_ADDRESS=192.168.1.10

# SSH to device
ssh root@192.168.1.10

# View logs
logread -f | grep esphome
```

### Debugging

Enable verbose logging by modifying the service or plugin code. Rebuild with debug symbols:

```bash
# Add to local.fragment
BR2_ENABLE_DEBUG=y
```

## Version Information

- **Package Version**: 0.0.1
- **Upstream**: [yinzara/esphome-linux](https://github.com/yinzara/esphome-linux)
- **License**: MIT

## References

- [ESPHome Documentation](https://esphome.io/)
- [ESPHome Native API](https://esphome.io/components/api.html)
- [Home Assistant ESPHome Integration](https://www.home-assistant.io/integrations/esphome/)
- [Thingino Firmware](https://github.com/themactep/thingino-firmware)
- [BlueZ D-Bus API](https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/doc)

## Contributing

Contributions are welcome! Please:

1. Test changes on actual hardware
2. Document new features or plugins
3. Follow existing code style
4. Submit pull requests to the Thingino firmware repository

For questions or support:
- Discord: https://discord.gg/xDmqS944zr
- Telegram: https://t.me/thingino
