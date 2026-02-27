# Installation Guide - Thingino Portal Lua

## Quick Start

### 1. Enable in Buildroot

```bash
# Navigate to Thingino firmware directory
cd /path/to/thingino-firmware

# Configure buildroot
make menuconfig

# Navigate to: Target packages → Thingino packages → thingino-portal-lua
# Enable: [*] thingino-portal-lua

# Save and exit
```

### 2. Build Firmware

```bash
# Clean build (recommended)
make clean

# Build firmware
make

# The portal will be included in the generated firmware image
```

### 3. Flash Firmware

```bash
# Flash to camera using your preferred method
# Example for USB flashing:
sudo dd if=output/images/thingino-*.bin of=/dev/sdX bs=1M

# Or use Thingino's flash tools
```

### 4. First Boot

After flashing and booting:

1. Camera will automatically start portal if no WiFi is configured
2. Look for WiFi network `THINGINO-XXXX` (XXXX = last 4 MAC digits)
3. Connect to the network (no password by default)
4. Open browser - will auto-redirect to configuration page
5. Configure WiFi, hostname, password
6. Camera reboots and connects to your network

## Detailed Installation

### Prerequisites

Ensure these packages are available in your buildroot configuration:

```bash
# Required dependencies (auto-selected)
BR2_PACKAGE_LUA=y
BR2_PACKAGE_THINGINO_UHTTPD=y
BR2_PACKAGE_DNSMASQ=y
BR2_PACKAGE_HOSTAPD=y
BR2_PACKAGE_WPA_SUPPLICANT=y
```

### Buildroot Configuration

#### Option 1: menuconfig

```bash
make menuconfig

# Navigate through menus:
Target packages  --->
  Thingino packages  --->
    [*] thingino-portal-lua
```

#### Option 2: defconfig

Add to your camera's defconfig file:

```bash
# In configs/cameras/your_camera_defconfig
BR2_PACKAGE_THINGINO_PORTAL_LUA=y
```

#### Option 3: Command Line

```bash
# Enable directly
echo "BR2_PACKAGE_THINGINO_PORTAL_LUA=y" >> .config
make olddefconfig
```

### Build Process

```bash
# Full clean build (safest)
make clean
make

# Or incremental build (faster)
make thingino-portal-lua-rebuild
make
```

### Verification

Check that files are included in the build:

```bash
# Check target files
ls -la output/target/var/www-portal/
ls -la output/target/etc/init.d/S41portal-lua

# Check in final image
mkdir -p /tmp/thingino-mount
sudo mount -o loop output/images/thingino-*.bin /tmp/thingino-mount
ls -la /tmp/thingino-mount/var/www-portal/
sudo umount /tmp/thingino-mount
```

## Manual Installation

If you need to install on an existing system:

### 1. Copy Files

```bash
# Create directories
mkdir -p /var/www-portal/{lua,a}
mkdir -p /root/.ssh

# Copy portal files
cp files/www/index.html /var/www-portal/
cp files/www/lua/portal.lua /var/www-portal/lua/
cp files/www/a/* /var/www-portal/a/

# Copy configuration files
cp files/etc/uhttpd-portal.conf /etc/
cp files/etc/dnsmasq-portal.conf /etc/
cp files/etc/udhcpd-portal.conf /etc/
cp files/etc/wpa-portal_ap.conf /etc/

# Copy init script
cp files/S41portal-lua /etc/init.d/
```

### 2. Set Permissions

```bash
# Make scripts executable
chmod +x /etc/init.d/S41portal-lua
chmod +x /var/www-portal/lua/portal.lua

# Set proper ownership
chown -R root:root /var/www-portal/
chown -R root:root /etc/init.d/S41portal-lua
```

### 3. Test Installation

```bash
# Test Lua script syntax
lua /var/www-portal/lua/portal.lua

# Test init script
/etc/init.d/S41portal-lua start

# Check processes
ps | grep -E "(uhttpd|dnsmasq|wpa_supplicant)"

# Test web access
curl http://172.16.0.1/

# Stop portal
/etc/init.d/S41portal-lua stop
```

## Configuration

### Network Settings

Default network configuration:

```bash
# Network segment
CNET=172.16.0

# IP assignments
Gateway: 172.16.0.1 (camera)
DHCP Range: 172.16.0.10 - 172.16.0.100
DNS Server: 172.16.0.1 (captive portal)
```

### Customization

#### Change Network Segment

Edit `/etc/init.d/S41portal-lua`:

```bash
# Change this line
CNET=192.168.100  # Custom network

# Update configuration files accordingly
sed -i 's/172\.16\.0/192.168.100/g' /etc/dnsmasq-portal.conf
sed -i 's/172\.16\.0/192.168.100/g' /etc/udhcpd-portal.conf
```

#### Modify Timeout

Edit `/var/www-portal/lua/portal.lua`:

```lua
-- Change timeout (in seconds)
CONFIG = {
    ttl_in_sec = 300,  -- 5 minutes instead of 10
    -- ...
}
```

#### Custom SSID Prefix

Edit `/etc/init.d/S41portal-lua`:

```bash
# Change SSID prefix in wpa config
sed -i 's/THINGINO-/MYCAM-/' /etc/wpa-portal_ap.conf
```

## Troubleshooting

### Portal Won't Start

```bash
# Check prerequisites
ip addr show  # Should have wlan0 interface
env | grep wlan  # Should be empty (no existing config)

# Check manually
/etc/init.d/S41portal-lua start

# Check logs
tail /tmp/portaldebug
dmesg | tail
```

### Can't Access Portal

```bash
# Check network
ip addr show wlan0  # Should have 172.16.0.1
ip route show  # Should have route to 172.16.0.0/24

# Check services
ps | grep uhttpd
ps | grep dnsmasq
netstat -ln | grep :80
```

### Build Errors

```bash
# Missing dependencies
make thingino-portal-lua-show-depends

# Clean and rebuild
make thingino-portal-lua-dirclean
make thingino-portal-lua

# Check package
make thingino-portal-lua-show-info
```

## Uninstallation

### From Buildroot

```bash
# Disable in config
make menuconfig
# Uncheck thingino-portal-lua

# Rebuild
make clean
make
```

### Manual Removal

```bash
# Stop portal
/etc/init.d/S41portal-lua stop

# Remove files
rm -rf /var/www-portal/
rm -f /etc/init.d/S41portal-lua
rm -f /etc/uhttpd-portal.conf
rm -f /etc/dnsmasq-portal.conf
rm -f /etc/udhcpd-portal.conf
rm -f /etc/wpa-portal_ap.conf
```

## Migration from Original Portal

### Automatic Migration

The Lua portal is designed as a drop-in replacement:

1. Disable original: `# BR2_PACKAGE_THINGINO_PORTAL is not set`
2. Enable Lua version: `BR2_PACKAGE_THINGINO_PORTAL_LUA=y`
3. Rebuild firmware
4. Flash to camera

### Manual Migration

If both are installed:

```bash
# Stop original portal
/etc/init.d/S41portal stop

# Start Lua portal
/etc/init.d/S41portal-lua start

# Remove original (optional)
rm -f /etc/init.d/S41portal
rm -rf /var/www-portal-old/  # if backed up
```

## Support

For installation issues:

1. Check [README.md](README.md) for usage information
2. Check [TECHNICAL.md](TECHNICAL.md) for implementation details
3. Review [CHANGELOG.md](CHANGELOG.md) for version information
4. Report issues with full system information and logs
