#!/bin/bash

# SD Card Detection and Monitoring Script for Thingino Firmware Flashing
# Provides real-time detection and safe identification of SD cards

set -euo pipefail

# Configuration
TIMEOUT_SECONDS=30
VERBOSE=false
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

COMMANDS:
    monitor     Monitor for SD card insertion (default)
    detect      Detect currently inserted SD cards
    list        List all storage devices
    wait        Wait for SD card insertion with timeout

OPTIONS:
    -t, --timeout SECONDS    Timeout for wait command (default: 30)
    -v, --verbose           Enable verbose output
    -d, --dry-run           Show what would be done without executing
    -h, --help              Show this help message

EXAMPLES:
    $0 monitor                    # Monitor for SD card insertion
    $0 detect                     # Detect currently inserted SD cards
    $0 wait -t 60                # Wait up to 60 seconds for SD card
    $0 list                       # List all storage devices

EOF
}

# Check if running as root for some operations
check_root() {
    if [[ $EUID -ne 0 ]] && [[ "$1" == "write" ]]; then
        log_error "Root privileges required for writing to devices"
        return 1
    fi
}

# Detect if a device is an SD card based on multiple criteria
is_sd_card() {
    local device="$1"
    local base_device="${device%[0-9]*}"  # Remove partition numbers

    # Check if device exists
    [[ -b "$device" ]] || return 1

    # Method 1: Check udev properties for explicit SD card identification
    local mmc_type=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "MMC_TYPE=" | cut -d= -f2)
    local id_drive_flash_sd=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "ID_DRIVE_FLASH_SD=" | cut -d= -f2)
    local id_bus=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "ID_BUS=" | cut -d= -f2)
    local id_type=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "ID_TYPE=" | cut -d= -f2)
    local removable=$(cat "/sys/block/$(basename "$base_device")/removable" 2>/dev/null || echo "0")

    # Method 2: Check device name patterns
    local device_name=$(basename "$device")

    # Explicit SD card detection via udev properties
    if [[ "$mmc_type" == "SD" ]] || [[ "$id_drive_flash_sd" == "1" ]]; then
        return 0
    fi

    # SD cards typically appear as:
    # - /dev/mmcblk* (built-in SD card readers)
    # - /dev/sd* with removable=1 (USB SD card readers)

    if [[ "$device_name" =~ ^mmcblk[0-9]+$ ]]; then
        # Built-in SD card reader - check if it's actually an SD card
        # Some eMMC devices also use mmcblk naming
        local card_type=$(cat "/sys/block/$(basename "$base_device")/device/type" 2>/dev/null || echo "")
        [[ "$VERBOSE" == "true" ]] && echo "Debug: device=$device, base_device=$base_device, card_type='$card_type'" >&2
        if [[ "$card_type" == "SD" ]] || [[ -z "$card_type" ]]; then
            return 0
        fi
    elif [[ "$device_name" =~ ^sd[a-z]+$ ]] && [[ "$removable" == "1" ]]; then
        # USB SD card reader - additional checks
        if [[ "$id_bus" == "usb" ]] || [[ "$id_type" == "disk" ]]; then
            return 0
        fi
    fi

    return 1
}

# Get detailed device information
get_device_info() {
    local device="$1"
    local base_device
    if [[ "$device" =~ mmcblk[0-9]+$ ]]; then
        # For mmcblk devices, the base device is the device itself
        base_device="$device"
    else
        # For sd devices, remove partition numbers
        base_device="${device%[0-9]*}"
    fi

    echo "Device: $device"
    echo "Base device: $base_device"

    # Size information
    if [[ -f "/sys/block/$(basename "$base_device")/size" ]]; then
        local sectors=$(cat "/sys/block/$(basename "$base_device")/size")
        local size_mb=$((sectors * 512 / 1024 / 1024))
        echo "Size: ${size_mb} MB"
    fi

    # Vendor and model
    local vendor=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "ID_VENDOR=" | cut -d= -f2 || echo "Unknown")
    local model=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "ID_MODEL=" | cut -d= -f2 || echo "Unknown")
    echo "Vendor: $vendor"
    echo "Model: $model"

    # Bus type
    local id_bus=$(udevadm info --query=property --name="$device" 2>/dev/null | grep "ID_BUS=" | cut -d= -f2 || echo "Unknown")
    echo "Bus: $id_bus"

    # Removable status
    local removable=$(cat "/sys/block/$(basename "$base_device")/removable" 2>/dev/null || echo "0")
    echo "Removable: $([[ "$removable" == "1" ]] && echo "Yes" || echo "No")"

    # File system information
    local fstype=$(blkid -o value -s TYPE "$device" 2>/dev/null || echo "Unknown")
    echo "Filesystem: $fstype"

    # UUID
    local uuid=$(blkid -o value -s UUID "$device" 2>/dev/null || echo "None")
    echo "UUID: $uuid"
}

# Verify device is ready for writing
verify_device_ready() {
    local device="$1"

    log_info "Verifying device $device is ready for writing..."

    # Check if device is mounted
    if mount | grep -q "^$device"; then
        log_warn "Device $device is currently mounted"
        return 1
    fi

    # Check if device is in use
    if lsof "$device" >/dev/null 2>&1; then
        log_warn "Device $device is currently in use"
        return 1
    fi

    # Check if device is writable
    if [[ ! -w "$device" ]]; then
        log_warn "Device $device is not writable (check permissions)"
        return 1
    fi

    # Test read access
    if ! dd if="$device" of=/dev/null bs=512 count=1 >/dev/null 2>&1; then
        log_warn "Cannot read from device $device"
        return 1
    fi

    log_success "Device $device is ready for writing"
    return 0
}

# Detect currently inserted SD cards
detect_sd_cards() {
    log_info "Scanning for SD cards..."

    local found_cards=()

    # Check all block devices
    # First check SD devices
    for device in /dev/sd[a-z]; do
        [[ -b "$device" ]] || continue

        [[ "$VERBOSE" == "true" ]] && echo "Debug: Checking device $device" >&2

        if is_sd_card "$device"; then
            found_cards+=("$device")
            log_success "Found SD card: $device"

            if [[ "$VERBOSE" == "true" ]]; then
                get_device_info "$device"
                echo "---"
            fi
        else
            [[ "$VERBOSE" == "true" ]] && echo "Debug: $device is not an SD card" >&2
        fi
    done

    # Then check MMC devices
    for device in /dev/mmcblk[0-9]*; do
        [[ -b "$device" ]] || continue

        # Skip partitions for initial detection
        [[ "$device" =~ p[0-9]+$ ]] && continue

        [[ "$VERBOSE" == "true" ]] && echo "Debug: Checking device $device" >&2

        if is_sd_card "$device"; then
            found_cards+=("$device")
            log_success "Found SD card: $device"

            if [[ "$VERBOSE" == "true" ]]; then
                get_device_info "$device"
                echo "---"
            fi
        else
            [[ "$VERBOSE" == "true" ]] && echo "Debug: $device is not an SD card" >&2
        fi
    done

    if [[ ${#found_cards[@]} -eq 0 ]]; then
        log_warn "No SD cards detected"
        return 1
    fi

    # Return the first found card
    echo "${found_cards[0]}"
    return 0
}

# Monitor for SD card insertion using udev
monitor_sd_cards() {
    log_info "Monitoring for SD card insertion... (Press Ctrl+C to stop)"

    udevadm monitor --subsystem-match=block --property | while read -r line; do
        if [[ "$line" =~ DEVNAME=(/dev/[^[:space:]]+) ]]; then
            local device="${BASH_REMATCH[1]}"

            # Skip partitions for monitoring
            [[ "$device" =~ [0-9]+$ ]] && continue

            if is_sd_card "$device"; then
                log_success "SD card detected: $device"

                # Wait a moment for device to be ready
                sleep 2

                if verify_device_ready "$device"; then
                    echo "$device"
                    return 0
                fi
            fi
        fi
    done
}

# Wait for SD card insertion with timeout
wait_for_sd_card() {
    log_info "Waiting for SD card insertion (timeout: ${TIMEOUT_SECONDS}s)..."

    # First check if one is already present
    if sd_card=$(detect_sd_cards 2>/dev/null); then
        log_success "SD card already present: $sd_card"
        echo "$sd_card"
        return 0
    fi

    # Monitor for new insertions with timeout
    timeout "$TIMEOUT_SECONDS" bash -c '
        udevadm monitor --subsystem-match=block --property | while read -r line; do
            if [[ "$line" =~ DEVNAME=(/dev/[^[:space:]]+) ]]; then
                device="${BASH_REMATCH[1]}"
                [[ "$device" =~ [0-9]+$ ]] && continue

                if '"$(declare -f is_sd_card)"'; is_sd_card "$device"; then
                    sleep 2
                    echo "$device"
                    exit 0
                fi
            fi
        done
    ' || {
        log_error "Timeout waiting for SD card insertion"
        return 1
    }
}

# List all storage devices
list_storage_devices() {
    log_info "Listing all storage devices:"

    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL,VENDOR | grep -E "(disk|part)"

    echo
    log_info "Detailed device information:"

    for device in /dev/sd* /dev/mmcblk*; do
        [[ -b "$device" ]] || continue
        [[ "$device" =~ [0-9]+$ ]] && continue

        echo "---"
        echo "Device: $device"

        if is_sd_card "$device"; then
            echo "Type: SD Card"
        else
            echo "Type: Other storage"
        fi

        get_device_info "$device"
    done
}

# Main function
main() {
    local command="monitor"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--timeout)
                TIMEOUT_SECONDS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            monitor|detect|list|wait)
                command="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Execute command
    case "$command" in
        monitor)
            monitor_sd_cards
            ;;
        detect)
            detect_sd_cards
            ;;
        list)
            list_storage_devices
            ;;
        wait)
            wait_for_sd_card
            ;;
        *)
            log_error "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
