# SD Card Detection and Flashing for Thingino

This document describes comprehensive methods for detecting, identifying, and safely writing thingino firmware to SD cards on Debian Linux systems.

## Overview

The SD card detection system provides multiple approaches for reliable SD card identification with extensive safety checks to prevent accidental data loss on system drives.

## Scripts Provided

### 1. `scripts/sd_card_monitor.sh`
Core detection and monitoring functionality with the following capabilities:

- **Real-time monitoring**: Uses `udevadm monitor` to detect SD card insertion events
- **Device identification**: Distinguishes SD cards from other storage devices using multiple criteria
- **Safety verification**: Checks mount status, write protection, and device accessibility
- **Cross-platform support**: Works with both USB SD card readers (`/dev/sdX`) and built-in slots (`/dev/mmcblkX`)

### 2. `scripts/sd_card_flasher.sh`
Complete firmware flashing solution with comprehensive safety features:

- **Automatic SD card detection**: Can auto-detect or use specified device
- **Firmware validation**: Checks firmware image integrity and recognizes common signatures
- **Safety checks**: Multiple validation layers to prevent accidental overwrites
- **Backup support**: Optional backup creation before flashing
- **Verification**: Post-flash verification using checksums

### 3. `scripts/sd_utils.sh`
Development utilities for common SD card operations:

- **Quick device discovery**: Find and list all SD cards
- **Device information**: Detailed device and partition information
- **Mount/unmount operations**: Safe mounting and unmounting
- **Formatting**: Format SD cards with proper partition tables
- **Cloning and backup**: Clone between SD cards or create backup images

## Detection Methods

### Method 1: Real-time udev Monitoring

```bash
# Monitor for SD card insertion
./scripts/sd_card_monitor.sh monitor

# Wait for SD card with timeout
./scripts/sd_card_monitor.sh wait -t 60
```

This method uses `udevadm monitor` to detect block device events in real-time. It's the most reliable method for detecting new SD card insertions.

### Method 2: Polling-based Detection

```bash
# Detect currently inserted SD cards
./scripts/sd_card_monitor.sh detect

# List all storage devices
./scripts/sd_card_monitor.sh list
```

This method scans existing block devices to find SD cards that are already inserted.

### Method 3: Manual Identification

```bash
# Check if specific device is an SD card
./scripts/sd_utils.sh check /dev/mmcblk0

# Get detailed device information
./scripts/sd_utils.sh info /dev/mmcblk0
```

## Device Identification Criteria

The scripts use multiple criteria to identify SD cards:

### 1. Device Name Patterns
- **Built-in SD readers**: `/dev/mmcblk[0-9]+`
- **USB SD readers**: `/dev/sd[a-z]+` with `removable=1`

### 2. udev Properties
- `ID_BUS=usb` for USB card readers
- `ID_TYPE=disk` for storage devices
- Device removable status from `/sys/block/*/removable`

### 3. Size Validation
- Reasonable size ranges for SD cards (64MB - 128GB)
- Warnings for unusually small or large devices

### 4. Hardware Properties
- Write protection status
- Vendor and model information
- Bus type identification

## Safety Checks

### Pre-write Validation
1. **Device existence**: Verify block device exists
2. **SD card verification**: Confirm device is actually an SD card
3. **Mount status**: Check if device or partitions are mounted
4. **Process usage**: Verify no processes are using the device
5. **Write permissions**: Confirm write access to device
6. **Read test**: Perform basic read operation to verify accessibility

### Firmware Validation
1. **File existence**: Verify firmware image file exists and is readable
2. **Size validation**: Check for reasonable firmware image sizes
3. **Signature detection**: Recognize common firmware signatures (U-Boot, kernel, SquashFS)
4. **User confirmation**: Require explicit confirmation for unusual images

## Usage Examples

### Basic Firmware Flashing

```bash
# Auto-detect SD card and flash firmware
sudo ./scripts/sd_card_flasher.sh firmware.bin

# Flash to specific device
sudo ./scripts/sd_card_flasher.sh firmware.bin /dev/mmcblk0

# Flash with backup
sudo ./scripts/sd_card_flasher.sh -b firmware.bin
```

### Development Workflow

```bash
# Find available SD cards
./scripts/sd_utils.sh find

# Check device safety
./scripts/sd_utils.sh check /dev/mmcblk0

# Format SD card for testing
sudo ./scripts/sd_utils.sh format /dev/mmcblk0

# Create backup before testing
./scripts/sd_utils.sh backup /dev/mmcblk0
```

### Monitoring for Development

```bash
# Monitor for SD card insertion during development
./scripts/sd_card_monitor.sh monitor

# Wait for SD card with verbose output
./scripts/sd_card_monitor.sh wait -v -t 120
```

## Integration with Thingino Build System

### Makefile Integration

Add these targets to your Makefile:

```makefile
# Flash firmware to SD card
flash_sd: $(FIRMWARE_BIN_FULL)
	@echo "Flashing firmware to SD card..."
	@scripts/sd_utils.sh find
	@scripts/sd_card_flasher.sh $(FIRMWARE_BIN_FULL)

# Prepare SD card for testing
prepare_sd:
	@echo "Preparing SD card..."
	@scripts/sd_utils.sh find
	@scripts/sd_utils.sh format /dev/mmcblk0

# Create SD card backup
backup_sd:
	@echo "Creating SD card backup..."
	@scripts/sd_utils.sh find
	@scripts/sd_utils.sh backup /dev/mmcblk0
```

### Automated Build and Flash

```bash
# Build and flash in one command
make clean && make && make flash_sd
```

## Error Handling

### Common Issues and Solutions

1. **Permission Denied**
   - Solution: Run with `sudo` for device access
   - Check: User permissions for block device access

2. **Device Not Found**
   - Solution: Verify SD card is properly inserted
   - Check: `dmesg` output for hardware detection

3. **Device Busy**
   - Solution: Unmount all partitions before flashing
   - Check: `lsof /dev/device` to find processes using device

4. **Write Protection**
   - Solution: Check physical write-protect switch on SD card
   - Check: `/sys/block/*/ro` file for write protection status

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# Verbose monitoring
./scripts/sd_card_monitor.sh monitor -v

# Verbose flashing
./scripts/sd_card_flasher.sh -v firmware.bin
```

## Platform Compatibility

### Tested Configurations

- **Debian 10, 11, 12**: Full compatibility
- **Ubuntu 18.04+**: Full compatibility
- **Built-in SD readers**: MMC/SD controllers
- **USB SD readers**: USB mass storage devices

### Hardware Support

- **Built-in SD slots**: Detected as `/dev/mmcblk*`
- **USB card readers**: Detected as `/dev/sd*`
- **Multi-slot readers**: Each slot detected separately
- **Write-protected cards**: Properly detected and rejected

## Security Considerations

### Data Protection

1. **Multiple confirmation prompts**: Prevent accidental overwrites
2. **Device type verification**: Ensure target is actually an SD card
3. **Size validation**: Warn about unusual device sizes
4. **Backup options**: Create backups before destructive operations

### System Safety

1. **Root privilege checks**: Only require root when necessary
2. **Mount point verification**: Prevent overwriting mounted filesystems
3. **Process checking**: Ensure no applications are using the device
4. **Read-only testing**: Verify device accessibility before writing

## Advanced Usage

### Custom udev Rules

For automatic actions on SD card insertion, create `/etc/udev/rules.d/99-sdcard-thingino.rules`:

```
# Auto-detect thingino SD cards
SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]", ACTION=="add", RUN+="/path/to/scripts/sd_card_monitor.sh detect"
SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTR{removable}=="1", ACTION=="add", RUN+="/path/to/scripts/sd_card_monitor.sh detect"
```

### Scripted Workflows

```bash
#!/bin/bash
# Automated firmware testing workflow

# Wait for SD card
echo "Please insert SD card for testing..."
DEVICE=$(./scripts/sd_card_monitor.sh wait -t 300)

if [[ $? -eq 0 ]]; then
    echo "SD card detected: $DEVICE"
    
    # Create backup
    ./scripts/sd_utils.sh backup "$DEVICE"
    
    # Flash firmware
    sudo ./scripts/sd_card_flasher.sh firmware.bin "$DEVICE"
    
    echo "Firmware flashed successfully!"
else
    echo "No SD card detected within timeout"
    exit 1
fi
```

## Troubleshooting

### Enable Debug Logging

```bash
# Enable udev debugging
udevadm control --log-priority=debug

# Monitor udev events
udevadm monitor --environment --udev

# Check device properties
udevadm info --query=all --name=/dev/mmcblk0
```

### Manual Device Verification

```bash
# Check device properties
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,VENDOR

# Check removable status
cat /sys/block/mmcblk0/removable

# Check device information
blkid /dev/mmcblk0

# Check mount status
mount | grep mmcblk0
```

This comprehensive solution provides reliable SD card detection and safe firmware flashing for thingino development across different Debian Linux configurations and hardware setups.
