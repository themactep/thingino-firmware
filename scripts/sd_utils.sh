#!/bin/bash

# SD Card Utilities for Thingino Development
# Quick utilities for SD card operations during development

set -euo pipefail

# Source the SD card monitor functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sd_card_monitor.sh"

show_utils_usage() {
    cat << EOF
Usage: $0 COMMAND [OPTIONS]

Quick utilities for SD card operations during thingino development.

COMMANDS:
    find            Find and list SD cards
    info DEVICE     Show detailed information about a device
    check DEVICE    Check if device is safe for writing
    mount DEVICE    Safely mount SD card
    unmount DEVICE  Safely unmount SD card
    format DEVICE   Format SD card (FAT32)
    clone SRC DST   Clone one SD card to another
    backup DEVICE   Create backup image of SD card

OPTIONS:
    -v, --verbose   Enable verbose output
    -h, --help      Show this help message

EXAMPLES:
    $0 find                     # Find all SD cards
    $0 info /dev/mmcblk0        # Show device information
    $0 check /dev/mmcblk0       # Check if device is safe for writing
    $0 mount /dev/mmcblk0       # Mount SD card
    $0 format /dev/mmcblk0      # Format SD card as FAT32
    $0 backup /dev/mmcblk0      # Create backup image

INTEGRATION WITH THINGINO BUILD:
    # In Makefile, add target for SD card flashing:
    flash_sd: \$(FIRMWARE_BIN_FULL)
        @scripts/sd_utils.sh find
        @scripts/sd_card_flasher.sh \$(FIRMWARE_BIN_FULL)

    # Quick SD card preparation:
    prepare_sd:
        @scripts/sd_utils.sh find
        @scripts/sd_utils.sh format /dev/mmcblk0

EOF
}

# Find and list all SD cards
find_sd_cards() {
    log_info "Searching for SD cards..."

    local found=false

    # Check SD devices
    for device in /dev/sd[a-z]; do
        [[ -b "$device" ]] || continue

        if is_sd_card "$device"; then
            found=true
            echo "SD Card: $device"

            if [[ "$VERBOSE" == "true" ]]; then
                get_device_info "$device" | sed 's/^/  /'
                echo
            fi
        fi
    done

    # Check MMC devices
    for device in /dev/mmcblk[0-9]*; do
        [[ -b "$device" ]] || continue
        [[ "$device" =~ p[0-9]+$ ]] && continue

        if is_sd_card "$device"; then
            found=true
            echo "SD Card: $device"

            if [[ "$VERBOSE" == "true" ]]; then
                get_device_info "$device" | sed 's/^/  /'
                echo
            fi
        fi
    done

    if [[ "$found" != "true" ]]; then
        log_warn "No SD cards found"
        return 1
    fi

    return 0
}

# Show device information
show_device_info() {
    local device="$1"

    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi

    echo "=== Device Information: $device ==="
    get_device_info "$device"

    echo
    echo "=== Partition Table ==="
    fdisk -l "$device" 2>/dev/null || log_warn "Cannot read partition table"

    echo
    echo "=== Mount Status ==="
    if mount | grep -q "^$device"; then
        mount | grep "^$device"
    else
        echo "Not mounted"
    fi

    echo
    echo "=== Safety Check ==="
    if verify_device_ready "$device" 2>/dev/null; then
        echo "✓ Device is safe for writing"
    else
        echo "✗ Device is NOT safe for writing"
    fi
}

# Check if device is safe for writing
check_device_safety() {
    local device="$1"

    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi

    log_info "Checking device safety: $device"

    # Check if it's an SD card
    if ! is_sd_card "$device"; then
        log_error "Device $device is not an SD card!"
        return 1
    fi

    # Check if ready for writing
    if verify_device_ready "$device"; then
        log_success "Device $device is safe for writing"
        return 0
    else
        log_error "Device $device is NOT safe for writing"
        return 1
    fi
}

# Safely mount SD card
mount_sd_card() {
    local device="$1"
    local mount_point="/mnt/sdcard"

    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi

    # Check if already mounted
    if mount | grep -q "^$device"; then
        log_info "Device $device is already mounted:"
        mount | grep "^$device"
        return 0
    fi

    # Create mount point if it doesn't exist
    if [[ ! -d "$mount_point" ]]; then
        log_info "Creating mount point: $mount_point"
        mkdir -p "$mount_point"
    fi

    # Try to mount
    log_info "Mounting $device to $mount_point"
    if mount "$device" "$mount_point"; then
        log_success "Successfully mounted $device to $mount_point"
        return 0
    else
        log_error "Failed to mount $device"
        return 1
    fi
}

# Safely unmount SD card
unmount_sd_card() {
    local device="$1"

    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi

    # Find all mounted partitions for this device
    local mounted_partitions=$(mount | grep "^$device" | awk '{print $1}')

    if [[ -z "$mounted_partitions" ]]; then
        log_info "Device $device is not mounted"
        return 0
    fi

    # Unmount each partition
    for partition in $mounted_partitions; do
        log_info "Unmounting $partition"
        if umount "$partition"; then
            log_success "Successfully unmounted $partition"
        else
            log_warn "Failed to unmount $partition"
        fi
    done

    # Sync to ensure all data is written
    sync

    log_success "Device $device unmounted and synced"
    return 0
}

# Format SD card as FAT32
format_sd_card() {
    local device="$1"

    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi

    # Safety checks
    if ! check_device_safety "$device"; then
        return 1
    fi

    # Confirmation
    echo
    log_warn "WARNING: This will destroy all data on $device!"
    read -p "Are you sure you want to format $device? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && {
        log_info "Format operation cancelled"
        return 1
    }

    # Unmount first
    unmount_sd_card "$device"

    # Create new partition table and format
    log_info "Creating new partition table on $device"
    if echo -e "o\nn\np\n1\n\n\nt\nb\nw" | fdisk "$device"; then
        log_success "Partition table created"
    else
        log_error "Failed to create partition table"
        return 1
    fi

    # Wait for partition to appear
    sleep 2

    # Format as FAT32
    local partition="${device}1"
    if [[ "$device" =~ mmcblk ]]; then
        partition="${device}p1"
    fi

    log_info "Formatting $partition as FAT32"
    if mkfs.vfat -F 32 -n "THINGINO" "$partition"; then
        log_success "Successfully formatted $partition"
        return 0
    else
        log_error "Failed to format $partition"
        return 1
    fi
}

# Clone one SD card to another
clone_sd_card() {
    local src_device="$1"
    local dst_device="$2"

    if [[ ! -b "$src_device" ]]; then
        log_error "Source device not found: $src_device"
        return 1
    fi

    if [[ ! -b "$dst_device" ]]; then
        log_error "Destination device not found: $dst_device"
        return 1
    fi

    # Safety checks
    if ! is_sd_card "$src_device"; then
        log_error "Source device $src_device is not an SD card"
        return 1
    fi

    if ! is_sd_card "$dst_device"; then
        log_error "Destination device $dst_device is not an SD card"
        return 1
    fi

    if ! verify_device_ready "$dst_device"; then
        log_error "Destination device $dst_device is not ready for writing"
        return 1
    fi

    # Get source device size
    local src_base
    if [[ "$src_device" =~ mmcblk[0-9]+$ ]]; then
        # For mmcblk devices, the base device is the device itself
        src_base="$src_device"
    else
        # For sd devices, remove partition numbers
        src_base="${src_device%[0-9]*}"
    fi
    local src_sectors=$(cat "/sys/block/$(basename "$src_base")/size")
    local src_size_mb=$((src_sectors * 512 / 1024 / 1024))

    # Confirmation
    echo
    log_warn "WARNING: This will overwrite all data on $dst_device!"
    log_info "Source: $src_device (${src_size_mb} MB)"
    log_info "Destination: $dst_device"
    read -p "Are you sure you want to clone? [y/N]: " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && {
        log_info "Clone operation cancelled"
        return 1
    }

    # Unmount both devices
    unmount_sd_card "$src_device"
    unmount_sd_card "$dst_device"

    # Clone
    log_info "Cloning $src_device to $dst_device (${src_size_mb} MB)"
    if dd if="$src_device" of="$dst_device" bs=1M status=progress; then
        sync
        log_success "Successfully cloned $src_device to $dst_device"
        return 0
    else
        log_error "Failed to clone SD card"
        return 1
    fi
}

# Create backup of SD card
backup_sd_card() {
    local device="$1"
    local backup_file="sdcard_backup_$(date +%Y%m%d_%H%M%S).img"

    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi

    # Get device size
    local base_device
    if [[ "$device" =~ mmcblk[0-9]+$ ]]; then
        # For mmcblk devices, the base device is the device itself
        base_device="$device"
    else
        # For sd devices, remove partition numbers
        base_device="${device%[0-9]*}"
    fi
    local sectors=$(cat "/sys/block/$(basename "$base_device")/size")
    local size_mb=$((sectors * 512 / 1024 / 1024))

    log_info "Creating backup of $device (${size_mb} MB) to $backup_file"

    if dd if="$device" of="$backup_file" bs=1M status=progress; then
        log_success "Backup created: $backup_file"
        log_info "To restore: dd if=$backup_file of=$device bs=1M status=progress"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# Main function
main() {
    local command=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_utils_usage
                exit 0
                ;;
            find|info|check|mount|unmount|format|clone|backup)
                command="$1"
                shift
                break
                ;;
            *)
                log_error "Unknown option: $1"
                show_utils_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$command" ]]; then
        log_error "No command specified"
        show_utils_usage
        exit 1
    fi

    # Execute command
    case "$command" in
        find)
            find_sd_cards
            ;;
        info)
            [[ $# -lt 1 ]] && { log_error "Device not specified"; exit 1; }
            show_device_info "$1"
            ;;
        check)
            [[ $# -lt 1 ]] && { log_error "Device not specified"; exit 1; }
            check_device_safety "$1"
            ;;
        mount)
            [[ $# -lt 1 ]] && { log_error "Device not specified"; exit 1; }
            mount_sd_card "$1"
            ;;
        unmount)
            [[ $# -lt 1 ]] && { log_error "Device not specified"; exit 1; }
            unmount_sd_card "$1"
            ;;
        format)
            [[ $# -lt 1 ]] && { log_error "Device not specified"; exit 1; }
            format_sd_card "$1"
            ;;
        clone)
            [[ $# -lt 2 ]] && { log_error "Source and destination devices not specified"; exit 1; }
            clone_sd_card "$1" "$2"
            ;;
        backup)
            [[ $# -lt 1 ]] && { log_error "Device not specified"; exit 1; }
            backup_sd_card "$1"
            ;;
        *)
            log_error "Unknown command: $command"
            show_utils_usage
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
