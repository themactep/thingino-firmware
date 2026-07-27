# Thingino Provisioning System

## Overview

The Thingino Provisioning System is a simple, automated configuration mechanism that allows devices to fetch and apply configuration settings from a remote server during boot. This system enables semi zero-touch deployment and centralized management of Thingino devices. It supports both device-specific configurations and shared common configurations for efficient device management.

The provisioning system is not included in production builds, but can be enabled by including `BR2_PACKAGE_THINGINO_PROVISION=y` in your build configuration.

## When to Use Provisioning

The provisioning system is ideal for:
- **Multiple Device Deployment**: Configure many devices with the same settings, and/or update configurations across all devices.
- **Remote Installation**: Pre-configure devices before shipping to installation sites

If you're managing more than a few devices or need reproducible configurations, provisioning will save significant time and could reduce errors.

## How It Works

### 1. Boot Process Integration

The provisioning system runs as an init script (`S98provision`) during the boot process. It executes after network initialization, towards the end of the boot process, ensuring network connectivity is available.

### 2. Configuration Discovery

The system uses two methods to discover the provisioning server:

#### Method 1: DHCP Option 160 (Recommended)
- Only supported in IPv4 networks
- The device requests DHCP option 160 during network initialization
- The DHCP server responds with the provisioning server URL
- This method enables automatic discovery without pre-configuration

#### Method 2: Manual Configuration
- Set the `provisioning_server` variable in the device configuration
- Useful for static network configurations or testing

### 3. Device Identification

The system identifies devices using their MAC address with the following priority:
1. **usb0** (USB network interface) - highest priority
2. **eth0** (Ethernet interface) - medium priority
3. **wlan0** (WiFi interface) - lowest priority

The MAC address is used to construct the configuration file name on the server.

### 4. Configuration Retrieval

The system attempts to download a device-specific configuration file:
1. First tries: `{server_url}/thingino-{mac_lowercase}.conf`
2. If not found, tries: `{server_url}/thingino-{mac_uppercase}.conf`
3. If neither exists, provisioning is skipped (not an error)

The server URL comes from DHCP option 160 or manual configuration and includes the protocol (http:// or https://).

### 4.1. Common Configuration Support

The system also supports shared configuration through a common config file:
- If `common_config=true` is set in the PROVISION section, the system will attempt to download `{server_url}/thingino-common.conf`
- Common configuration is applied first, then device-specific configuration overrides it
- This allows sharing base settings across multiple devices while maintaining device-specific customizations

### 5. Configuration Processing

Downloaded configuration files are validated and processed in five sections:
- **AUTH**: Authentication credentials (required)
- **PROVISION**: Provisioning process control settings
- **UENV**: U-Boot environment variables
- **SYSTEM**: Thingino system configuration
- **USER**: Custom shell commands

After successful processing, the system reboots by default (unless disabled in PROVISION section).

## DHCP Option 160 Setup

To configure DHCP option 160 on your network, consult your router or network administrator documentation. The option should be set to the full URL of your provisioning server including the protocol (e.g., `http://192.168.1.10:8080` or `https://provision.lan`).

### Provisioning Server Setup

The provisioning server can be any HTTP(S) server (Apache, Nginx, etc.) serving configuration files.

## Configuration File Format

Configuration files must:
1. Start with the marker `!THINGINO-CONFIG` on the first line
2. Use INI-style sections: `[SECTION_NAME]`
3. Be named `thingino-{MAC_ADDRESS}.conf`

### Sample Configuration File

```ini
!THINGINO-CONFIG

[AUTH]
# Authentication (required) - use generated hash
password_hash=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456

[PROVISION]
# Provisioning process control
reboot=true
common_config=false

[UENV]
# U-Boot environment variables
# These are applied using fw_setenv
timezone=America/New_York
ntp_server=pool.ntp.org
wifi_ssid=MyNetwork
wifi_pass=MyPassword

[SYSTEM]
# Thingino system configuration
# These are applied using the 'conf' command
hostname=my-camera-01
motion_detection=true
rtsp_enabled=true
rtsp_port=554
web_port=80
admin_password=newpassword

[USER]
# Custom shell commands
# These are executed as shell scripts
echo "Device provisioned at $(date)" >> /tmp/provision.log
# Configure custom LED pattern
echo 1 > /sys/class/leds/status/brightness
# Install custom packages (if available)
# opkg update && opkg install custom-package
```

## Configuration Sections

### AUTH Section (Required)
**Authentication is mandatory for all provisioning.** This section provides secure authentication using device-specific password hashes.

#### How Authentication Works
The system uses salted SHA256 hashes for password authentication. The hash is generated using the device's SoC serial number as salt:

```bash
# Hash generation formula
hash = sha256(soc_serial + ":" + password)
```

#### Password Requirements:
- **Minimum 8 characters**
- **At least one lowercase letter** (a-z)
- **At least one uppercase letter** (A-Z)
- **At least one special character** (non-alphanumeric)

#### Setup Process:

**Step 1: Generate password hash on device**
```bash
# Generate and store password hash (run this on the device)
/etc/init.d/S98provision genpw
# Enter password when prompted (hidden input)
# Hash is automatically saved to device configuration
# Output displays hash for use in config file
```

**Step 2: Create config file with the same hash**
```ini
[AUTH]
password_hash=a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456
```

#### Important Notes:
- The hash is device-specific (uses SoC serial number as salt)
- You must run `genpw` on each device individually
- Device MUST have `provisioning_password_hash` set or provisioning fails
- Config file MUST have AUTH section with matching `password_hash` or provisioning fails
- No plain text passwords are stored on the device

### PROVISION Section
Controls the provisioning process behavior. Available settings:
- `reboot`: Whether to reboot after successful provisioning (default: `true`)
- `common_config`: Whether to download and apply common configuration (default: `false`)

Examples:
```ini
# Standard provisioning with reboot (default)
[PROVISION]
reboot=true

# Testing/development - no reboot
[PROVISION]
reboot=false

# Use common configuration with device-specific overrides
[PROVISION]
reboot=true
common_config=true
```

When `common_config=true`, the system will:
1. Download `thingino-common.conf` from the provisioning server
2. Apply all settings from the common config file first
3. Download the device-specific config file
4. Apply device-specific settings, overriding any conflicting common settings

#### How Overrides Work:
- **Common config sets defaults** → Device config customizes
- **Same setting in both files** → Device config wins
- **Settings only in common** → Applied to all devices
- **Settings only in device config** → Applied to that device only

#### Practical Example:
```ini
# thingino-common.conf - Shared across all cameras
[UENV]
wifi_ssid=CompanyWiFi          # All devices use same network
wifi_pass=SecurePassword123
timezone=America/New_York      # All devices in same timezone
ntp_server=pool.ntp.org

[SYSTEM]
rtsp_enabled=true              # All devices stream video
rtsp_port=554
motion_detection=true          # All devices detect motion

# thingino-001122aabbcc.conf - Specific device overrides
[SYSTEM]
hostname=front-entrance        # Unique per device
rtsp_port=8554                # This device uses different port
web_port=8080                 # This device gets unique web port
```

### UENV Section
Sets U-Boot environment variables using `fw_setenv`. Common variables include:
- `timezone`: System timezone
- `ntp_server`: NTP server for time synchronization
- `wifi_ssid`: WiFi network name
- `wifi_pass`: WiFi password

### SYSTEM Section
Configures Thingino system settings using the `conf` command. Examples:
- `hostname`: Device hostname (will be applied on next boot)
- `motion_detection`: Enable/disable motion detection
- `rtsp_enabled`: Enable/disable RTSP streaming
- `web_port`: Web interface port
- `admin_password`: Admin password

### USER Section
Executes custom shell commands for advanced configuration:
- Custom service configuration
- Package installation
- File modifications
- Custom scripts

## File Naming Convention

Configuration files must follow this naming pattern:
- `thingino-{MAC_ADDRESS}.conf`
- MAC address without colons (e.g., `001122334455`)
- Both lowercase and uppercase MAC addresses are supported

### Examples
- Device with MAC `00:11:22:aa:bb:cc`:
  - `thingino-001122aabbcc.conf` (lowercase)
  - `thingino-001122AABBCC.conf` (uppercase)

## Provisioning Status

### Completion Tracking
- After successful provisioning, the system sets `provisioning_complete=true` using the `conf` command
- The system reboots after successful provisioning by default (unless `reboot=false` in PROVISION section)
- Subsequent boots skip provisioning if this flag is set
- To re-provision, remove this flag: `conf d provisioning_complete`

### Logging
The provisioning system logs all activities to syslog.

## System Configuration

### SSL Certificate Validation
SSL certificate validation can be controlled system-wide using the configuration system:

```bash
# Enable SSL validation (default)
conf s provision_validate_ssl true

# Disable SSL validation (for self-signed certificates)
conf s provision_validate_ssl false
```

This setting affects the download of provisioning configuration files from HTTPS servers. When disabled, the system will accept self-signed certificates or certificates from untrusted CAs.

## Troubleshooting

### Common Issues

1. **Authentication failed**
   - Generate password hash on device: `/etc/init.d/S98provision genpw`
   - Verify config file has matching `[AUTH]` section with `password_hash`
   - Ensure passwords meet security requirements (8+ chars, uppercase, lowercase, special character)
   - Check that hash was generated on the correct device (SoC serial specific)
   - Verify device has `provisioning_password_hash` set: `conf g provisioning_password_hash`

2. **No provisioning server configured**
   - Ensure DHCP option 160 is set, or manually configure `provisioning_server`

3. **Configuration file not found**
   - Verify MAC address format in filename
   - Check server accessibility
   - Ensure HTTP server is running

4. **Invalid configuration file**
   - Verify `!THINGINO-CONFIG` marker is present
   - Check file syntax and encoding
   - Ensure `[AUTH]` section is present and properly formatted

## Security Considerations

1. **Network Security**: Use HTTPS URLs in DHCP option 160 for secure provisioning
2. **Authentication**: Use unique passwords per device in AUTH section for additional security
3. **SSL Certificate Validation**: Use `conf s provision_validate_ssl false` only for self-signed certificates or internal CAs
4. **Access Control**: Restrict provisioning server access
5. **Configuration Validation**: Validate configuration content
6. **Password Management**: Use strong, unique passwords for each device (enforced: 8+ chars, mixed case, special characters)

## Best Practices

1. **Version Control**: Keep configuration files in version control
2. **Testing**: Test configurations on development devices first
3. **Backup**: Backup working configurations before changes
4. **Documentation**: Document custom USER section commands
5. **Common Configuration**: Use `thingino-common.conf` with `common_config=true` for shared settings across multiple devices, then use device-specific configs for customizations
