# SD Card Detection and Flashing Scripts

This directory contains comprehensive SD card detection and firmware flashing utilities for the thingino project.

## Scripts Overview

### Core Scripts

1. **`sd_card_monitor.sh`** - Core detection and monitoring functionality
   - Real-time SD card insertion monitoring
   - Device identification and validation
   - Cross-platform compatibility (USB readers and built-in slots)

2. **`sd_card_flasher.sh`** - Safe firmware flashing with comprehensive checks
   - Automatic SD card detection
   - Firmware validation and safety checks
   - Backup and verification options

3. **`sd_utils.sh`** - Development utilities for SD card operations
   - Quick device discovery and information
   - Mount/unmount operations
   - Formatting and cloning utilities

### Test and Documentation

4. **`test_sd_detection.sh`** - Test suite for validation
5. **`README.md`** - This documentation file

## Quick Start

### Find SD Cards
```bash
# Find all SD cards
./scripts/sd_utils.sh find

# Get detailed device information
./scripts/sd_utils.sh info /dev/mmcblk0
```

### Monitor for SD Card Insertion
```bash
# Monitor for new SD card insertion
./scripts/sd_card_monitor.sh monitor

# Wait for SD card with timeout
./scripts/sd_card_monitor.sh wait -t 60
```

### Flash Firmware
```bash
# Auto-detect SD card and flash firmware
sudo ./scripts/sd_card_flasher.sh firmware.bin

# Flash to specific device with backup
sudo ./scripts/sd_card_flasher.sh -b firmware.bin /dev/mmcblk0
```

## Safety Features

### Device Identification
- Distinguishes SD cards from system drives using multiple criteria
- Checks udev properties (`MMC_TYPE=SD`, `ID_DRIVE_FLASH_SD=1`)
- Validates device name patterns and removable status
- Cross-references hardware properties

### Pre-write Safety Checks
- Verifies device is not mounted
- Checks for processes using the device
- Validates write permissions
- Tests device accessibility
- Confirms device is actually an SD card

### Firmware Validation
- Checks firmware image existence and readability
- Validates reasonable file sizes
- Recognizes common firmware signatures (U-Boot, kernel, SquashFS)
- Requires user confirmation for unusual images

## Integration with Thingino Build

### Makefile Targets

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

### Automated Workflow

```bash
# Complete build and flash workflow
make clean && make && make flash_sd
```

## Platform Compatibility

### Tested Systems
- Debian 10, 11, 12
- Ubuntu 18.04+
- Built-in SD card readers (MMC controllers)
- USB SD card readers

### Device Support
- **Built-in SD slots**: `/dev/mmcblk*` devices
- **USB card readers**: `/dev/sd*` devices with removable=1
- **Multi-slot readers**: Each slot detected separately
- **Write-protected cards**: Properly detected and rejected

## Error Handling

### Common Issues

1. **Permission Denied**
   ```bash
   # Solution: Run with sudo for device access
   sudo ./scripts/sd_card_flasher.sh firmware.bin
   ```

2. **Device Busy/Mounted**
   ```bash
   # Solution: Unmount before flashing
   ./scripts/sd_utils.sh unmount /dev/mmcblk0
   ```

3. **No SD Card Detected**
   ```bash
   # Check hardware detection
   dmesg | tail
   lsblk
   ```

### Debug Mode

Enable verbose output for troubleshooting:

```bash
# Verbose monitoring
./scripts/sd_card_monitor.sh monitor -v

# Verbose flashing
./scripts/sd_card_flasher.sh -v firmware.bin
```

## Advanced Usage

### Custom Detection Logic

The scripts can be sourced to use individual functions:

```bash
#!/bin/bash
source scripts/sd_card_monitor.sh

# Use detection functions in your own scripts
if is_sd_card "/dev/mmcblk0"; then
    echo "Device is an SD card"
fi
```

### Automated Testing

```bash
# Run test suite
./scripts/test_sd_detection.sh

# Basic functionality test
./scripts/sd_utils.sh find && echo "Detection working"
```

## Security Considerations

### Data Protection
- Multiple confirmation prompts prevent accidental overwrites
- Device type verification ensures target is actually an SD card
- Size validation warns about unusual device sizes
- Backup options create safety copies before destructive operations

### System Safety
- Root privileges only required when necessary
- Mount point verification prevents overwriting mounted filesystems
- Process checking ensures no applications are using the device
- Read-only testing verifies device accessibility before writing

## Dependencies

### Required System Commands
- `udevadm` - Device information and monitoring
- `lsblk` - Block device listing
- `blkid` - Block device identification
- `mount`/`umount` - Mount operations
- `fdisk` - Partition management
- `dd` - Low-level device operations
- `sync` - Filesystem synchronization

### Optional Commands
- `mkfs.vfat` - FAT32 formatting
- `mkfs.exfat` - exFAT formatting
- `lsof` - Process checking
- `sha256sum` - Verification checksums

## Contributing

When modifying these scripts:

1. Maintain backward compatibility
2. Add comprehensive error handling
3. Update documentation
4. Test on multiple platforms
5. Preserve safety checks

## License

These scripts are part of the thingino firmware project and follow the same licensing terms.
