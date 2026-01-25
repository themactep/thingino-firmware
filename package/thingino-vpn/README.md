# Thingino VPN Abstraction

This package provides a virtual package abstraction for selecting a VPN solution for thingino.

## Supported VPN Solutions

The following VPN solutions are supported:

### None
- No VPN solution included
- Minimizes flash usage

### WireGuard (default)
- Fast, modern, secure VPN tunnel
- Minimal overhead
- Included in Linux kernel (when available) or as kernel module
- Uses wireguard-tools for configuration
- Website: https://www.wireguard.com/

### ZeroTier-One
- Creates virtual Ethernet networks
- Appears as a virtual network interface
- Works like you are on the same physical LAN
- Requires C++ toolchain and thread support
- Website: https://www.zerotier.com/

### Tailscale
- WireGuard-based mesh VPN
- Centralized coordination and management
- Easy to set up and manage
- Requires flash size >= 16MB
- Website: https://tailscale.com/

## Usage

When building thingino firmware, select one VPN solution from the configuration menu:

```
Thingino Firmware → Extra Packages → VPN Selection
```

Only one VPN solution can be selected at a time to minimize flash usage.

## Requirements

### ZeroTier-One
- Toolchain with C++ support (BR2_INSTALL_LIBSTDCPP)
- Toolchain with thread support (BR2_TOOLCHAIN_HAS_THREADS)

### Tailscale
- Flash size >= 16MB

## Configuration

Each VPN solution has its own configuration files:

- **WireGuard**: Configuration via `/etc/wireguard/`
- **ZeroTier-One**: Configuration via `/var/lib/zerotier-one/`
- **Tailscale**: Configuration via Tailscale CLI and web interface
