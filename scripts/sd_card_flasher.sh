#!/bin/bash

# SD Card Firmware Copier for Thingino
# Copy firmware file to SD card for auto-update

set -euo pipefail

# Source the SD card monitor functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/sd_card_monitor.sh"

# Configuration
FIRMWARE_IMAGE=""
TARGET_MOUNT_POINT=""
FORCE_COPY=false
BACKUP_BEFORE_COPY=false
FIRMWARE_FILENAME="autoupdate-full.bin"

show_flasher_usage() {
    cat << EOF
Usage: $0 [OPTIONS] FIRMWARE_IMAGE [TARGET_MOUNT_POINT]

Copy thingino firmware to SD card as autoupdate-full.bin for auto-update.

ARGUMENTS:
    FIRMWARE_IMAGE      Path to the firmware image file
    TARGET_MOUNT_POINT  Target SD card mount point (optional, will auto-detect)

OPTIONS:
    -f, --force         Force copy without additional confirmations
    -b, --backup        Create backup of existing autoupdate-full.bin
    -v, --verbose       Enable verbose output
    -h, --help          Show this help message

EXAMPLES:
    $0 firmware.bin                           # Auto-detect SD card and copy
    $0 firmware.bin /media/user/sdcard        # Copy to specific mount point
    $0 -b firmware.bin                        # Create backup before copying
    $0 --force firmware.bin                   # Skip confirmations

FEATURES:
    - Automatic SD card mount point detection
    - Firmware file validation
    - Optional backup of existing firmware
    - Proper file permissions setting

EOF
}

# Validate firmware image
validate_firmware_image() {
    local image="$1"

    log_info "Validating firmware image: $image"

    # Check if file exists
    if [[ ! -f "$image" ]]; then
        log_error "Firmware image not found: $image"
        return 1
    fi

    # Check if file is readable
    if [[ ! -r "$image" ]]; then
        log_error "Cannot read firmware image: $image"
        return 1
    fi

    # Get file size
    local size=$(stat -c%s "$image")
    local size_mb=$((size / 1024 / 1024))

    log_info "Firmware image size: ${size_mb} MB"

    # Basic size validation (should be reasonable for embedded firmware)
    if [[ $size -lt 1048576 ]]; then  # Less than 1MB
        log_warn "Firmware image seems very small (${size_mb} MB)"
        if [[ "$FORCE_COPY" != "true" ]]; then
            read -p "Continue anyway? [y/N]: " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
        fi
    elif [[ $size -gt 1073741824 ]]; then  # Greater than 1GB
        log_warn "Firmware image seems very large (${size_mb} MB)"
        if [[ "$FORCE_COPY" != "true" ]]; then
            read -p "Continue anyway? [y/N]: " -n 1 -r
            echo
            [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
        fi
    fi

    # Check for common firmware file signatures
    local magic=$(xxd -l4 -ps "$image" 2>/dev/null || echo "")
    case "$magic" in
        "06050403")
            log_info "Detected U-Boot image signature"
            ;;
        "27051956")
            log_info "Detected kernel image signature"
            ;;
        "68737173")
            log_info "Detected SquashFS signature"
            ;;
        *)
            log_warn "Unknown firmware signature: $magic"
            ;;
    esac

    log_success "Firmware image validation passed"
    return 0
}

# Find SD card mount points
find_sd_mount_points() {
    log_info "Searching for SD card mount points..."

    local mount_points=()

    # Check all mounted filesystems for SD cards
    while IFS= read -r line; do
        local device=$(echo "$line" | awk '{print $1}')
        local mount_point=$(echo "$line" | awk '{print $3}')

        # Skip if not a block device
        [[ "$device" =~ ^/dev/ ]] || continue

        # Get base device (remove partition numbers)
        local base_device
        if [[ "$device" =~ mmcblk[0-9]+p[0-9]+$ ]]; then
            base_device="${device%p[0-9]*}"
        elif [[ "$device" =~ sd[a-z]+[0-9]+$ ]]; then
            base_device="${device%[0-9]*}"
        else
            continue
        fi

        # Check if it's an SD card
        if is_sd_card "$base_device"; then
            mount_points+=("$mount_point")
            log_success "Found SD card mount point: $mount_point ($device)"
        fi
    done < <(mount | grep -E "^/dev/(mmcblk|sd)")

    if [[ ${#mount_points[@]} -eq 0 ]]; then
        log_warn "No mounted SD cards found"
        return 1
    fi

    # Return the first mount point
    echo "${mount_points[0]}"
    return 0
}

# Check and reformat filesystem if needed
check_and_reformat_filesystem() {
    local mount_point="$1"

    # Get the device from mount point
    local device=$(df "$mount_point" | tail -1 | awk '{print $1}')
    log_info "Checking filesystem on device: $device"

    # Get base device (remove partition numbers)
    local base_device
    if [[ "$device" =~ mmcblk[0-9]+p[0-9]+$ ]]; then
        base_device="${device%p[0-9]*}"
    elif [[ "$device" =~ sd[a-z]+[0-9]+$ ]]; then
        base_device="${device%[0-9]*}"
    else
        base_device="$device"
    fi

    # Get filesystem type
    local fs_type=$(lsblk -no FSTYPE "$device" 2>/dev/null || echo "unknown")
    log_info "Current filesystem type: $fs_type"

    # Check if it's FAT (vfat/fat32)
    if [[ "$fs_type" == "vfat" ]]; then
        log_success "Filesystem is already FAT32, no reformatting needed"
        return 0
    fi

    # Need to reformat
    log_warn "Filesystem is $fs_type, but FAT32 is recommended for camera compatibility"
    echo
    log_warn "WARNING: Reformatting will destroy all data on the SD card!"
    read -p "Reformat SD card to FAT32? [y/N]: " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping current filesystem. Note: Some cameras may have compatibility issues."
        return 0
    fi

    # Proceed with reformatting
    log_info "Reformatting $base_device to FAT32..."

    # Unmount first
    if ! sudo umount "$mount_point"; then
        log_error "Failed to unmount $mount_point"
        return 1
    fi

    # Create new partition table and format
    log_info "Creating new partition table on $base_device..."
    if ! echo -e "o\nn\np\n1\n\n\nt\n1\nb\nw" | sudo fdisk "$base_device" >/dev/null 2>&1; then
        log_error "Failed to create partition table"
        return 1
    fi

    # Wait for partition to appear
    sleep 2

    # Determine partition name
    local partition
    if [[ "$base_device" =~ mmcblk ]]; then
        partition="${base_device}p1"
    else
        partition="${base_device}1"
    fi

    # Format as FAT32
    log_info "Formatting $partition as FAT32..."
    if ! sudo mkfs.vfat -F 32 -n "THINGINO" "$partition" >/dev/null 2>&1; then
        log_error "Failed to format partition"
        return 1
    fi

    # Remount
    log_info "Remounting SD card..."
    sleep 2

    # Try to remount (system should auto-mount)
    local retry_count=0
    while [[ $retry_count -lt 10 ]]; do
        if mount | grep -q "$partition"; then
            local new_mount_point=$(mount | grep "$partition" | awk '{print $3}')
            log_success "SD card reformatted and remounted at: $new_mount_point"
            # Update the global variable
            TARGET_MOUNT_POINT="$new_mount_point"
            return 0
        fi
        sleep 1
        ((retry_count++))
    done

    log_error "SD card was reformatted but failed to auto-mount"
    log_info "Please manually mount the SD card and try again"
    return 1
}

# Validate target mount point
validate_target_mount_point() {
    local mount_point="$1"

    log_info "Validating target mount point: $mount_point"

    # Check if mount point exists
    if [[ ! -d "$mount_point" ]]; then
        log_error "Mount point not found: $mount_point"
        return 1
    fi

    # Check if it's actually a mount point
    if ! mountpoint -q "$mount_point"; then
        log_error "$mount_point is not a mount point"
        return 1
    fi

    # Check if it's writable
    if [[ ! -w "$mount_point" ]]; then
        log_error "Mount point $mount_point is not writable"
        return 1
    fi

    # Get filesystem info
    local fs_info=$(df -h "$mount_point" | tail -1)
    log_info "Filesystem info: $fs_info"

    # Check and potentially reformat filesystem
    if ! check_and_reformat_filesystem "$mount_point"; then
        return 1
    fi

    log_success "Target mount point validation passed"
    return 0
}

# Create backup of existing firmware file
create_backup() {
    local mount_point="$1"
    local firmware_path="$mount_point/$FIRMWARE_FILENAME"

    if [[ ! -f "$firmware_path" ]]; then
        log_info "No existing firmware file to backup"
        return 0
    fi

    local backup_file="${firmware_path}.backup.$(date +%Y%m%d_%H%M%S)"

    log_info "Creating backup of existing firmware file"
    log_info "Backup: $backup_file"

    if cp "$firmware_path" "$backup_file"; then
        log_success "Backup created: $backup_file"
        return 0
    else
        log_error "Failed to create backup"
        return 1
    fi
}

# Copy firmware to SD card
copy_firmware() {
    local image="$1"
    local mount_point="$2"
    local target_path="$mount_point/$FIRMWARE_FILENAME"

    log_info "Copying firmware $image to $target_path"

    # Final confirmation unless forced
    if [[ "$FORCE_COPY" != "true" ]]; then
        echo
        log_warn "This will copy the firmware file to the SD card as $FIRMWARE_FILENAME"
        log_warn "Source: $image"
        log_warn "Target: $target_path"
        echo
        read -p "Continue? [Y/n]: " -n 1 -r
        echo
        [[ $REPLY =~ ^[Nn]$ ]] && {
            log_info "Copy operation cancelled by user"
            return 1
        }
    fi

    # Copy the firmware
    log_info "Copying firmware file..."
    if cp "$image" "$target_path"; then
        log_success "Firmware copied successfully"

        # Set proper permissions
        chmod 644 "$target_path"

        # Sync to ensure data is written
        sync

        # Show file info
        local file_size=$(stat -c%s "$target_path")
        local size_mb=$((file_size / 1024 / 1024))
        log_info "File size: ${size_mb} MB"
        log_info "File location: $target_path"

        return 0
    else
        log_error "Failed to copy firmware file"
        return 1
    fi
}

# Verify copied firmware
verify_firmware() {
    local image="$1"
    local mount_point="$2"
    local target_path="$mount_point/$FIRMWARE_FILENAME"

    log_info "Verifying copied firmware..."

    if [[ ! -f "$target_path" ]]; then
        log_error "Target firmware file not found: $target_path"
        return 1
    fi

    # Compare checksums
    local original_checksum=$(sha256sum "$image" | cut -d' ' -f1)
    local copied_checksum=$(sha256sum "$target_path" | cut -d' ' -f1)

    if [[ "$original_checksum" == "$copied_checksum" ]]; then
        log_success "Firmware verification passed"
        return 0
    else
        log_error "Firmware verification failed!"
        log_error "Original checksum: $original_checksum"
        log_error "Copied checksum:   $copied_checksum"
        return 1
    fi
}

# Auto-detect SD card mount point
auto_detect_sd_mount_point() {
    log_info "Auto-detecting SD card mount point..."

    if mount_point=$(find_sd_mount_points 2>/dev/null); then
        echo "$mount_point"
        return 0
    fi

    log_error "No mounted SD card found"
    log_info "Please ensure your SD card is inserted and mounted"
    return 1
}

# Main copy function
main_copy() {
    # Validate firmware image
    if ! validate_firmware_image "$FIRMWARE_IMAGE"; then
        exit 1
    fi

    # Determine target mount point
    if [[ -z "$TARGET_MOUNT_POINT" ]]; then
        if ! TARGET_MOUNT_POINT=$(auto_detect_sd_mount_point); then
            log_error "Failed to detect SD card mount point"
            exit 1
        fi
    fi

    # Validate target mount point
    if ! validate_target_mount_point "$TARGET_MOUNT_POINT"; then
        exit 1
    fi

    # Show mount point information
    log_info "Target mount point: $TARGET_MOUNT_POINT"
    log_info "Target file: $TARGET_MOUNT_POINT/$FIRMWARE_FILENAME"

    # Create backup if requested
    if [[ "$BACKUP_BEFORE_COPY" == "true" ]]; then
        if ! create_backup "$TARGET_MOUNT_POINT"; then
            exit 1
        fi
    fi

    # Copy firmware
    if ! copy_firmware "$FIRMWARE_IMAGE" "$TARGET_MOUNT_POINT"; then
        exit 1
    fi

    # Verify copy
    if ! verify_firmware "$FIRMWARE_IMAGE" "$TARGET_MOUNT_POINT"; then
        log_warn "Verification failed, but copy may have succeeded"
    fi

    log_success "Firmware copy completed successfully!"
    log_info "The firmware file is now available as $FIRMWARE_FILENAME on the SD card"
    log_info "The camera will auto-update when it boots with this SD card"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                FORCE_COPY=true
                shift
                ;;
            -b|--backup)
                BACKUP_BEFORE_COPY=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_flasher_usage
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                show_flasher_usage
                exit 1
                ;;
            *)
                if [[ -z "$FIRMWARE_IMAGE" ]]; then
                    FIRMWARE_IMAGE="$1"
                elif [[ -z "$TARGET_MOUNT_POINT" ]]; then
                    TARGET_MOUNT_POINT="$1"
                else
                    log_error "Too many arguments"
                    show_flasher_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$FIRMWARE_IMAGE" ]]; then
        log_error "Firmware image not specified"
        show_flasher_usage
        exit 1
    fi
}

# Main function
main() {
    # Parse arguments first to handle help
    parse_args "$@"

    # Execute main copy logic (no root privileges needed for file copy)
    main_copy

    sync
    sudo umount "$TARGET_MOUNT_POINT"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
