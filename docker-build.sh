#!/bin/bash
#
# Container wrapper for Thingino firmware build
# Provides non-interactive containerized build environment
#
# Usage:
#   ./docker-build.sh            # Build firmware (fast parallel)
#   ./docker-build.sh dev        # Debug build (slow serial, stops at errors)
#   ./docker-build.sh menuconfig # Run menuconfig in container
#   ./docker-build.sh shell      # Open interactive shell
#   ./docker-build.sh clean      # Clean build in container
#   ./docker-build.sh upgrade_ota # Upgrade firmware OTA
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect container engine
if command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE="podman"
    print_info "Using Podman"
elif command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE="docker"
    print_info "Using Docker"
else
    print_error "Neither Podman nor Docker found. Please install one of them."
    echo
    echo "Install Podman:"
    echo "  sudo apt update && sudo apt install podman"
    echo
    echo "Or install Docker:"
    echo "  curl -fsSL https://get.docker.com | sudo sh"
    exit 1
fi

# Build image if needed
DOCKER_IMAGE="thingino-builder"
DOCKER_TAG="latest"

if ! $CONTAINER_ENGINE images | grep -q "$DOCKER_IMAGE.*$DOCKER_TAG"; then
    print_info "Building container image..."
    make -f Makefile.docker docker-build CONTAINER_ENGINE="$CONTAINER_ENGINE"
    print_success "Container image built"
else
    print_info "Container image already exists"
fi

# Function to select camera
select_camera() {
    local cameras_dir="configs/cameras${GROUP:+-$GROUP}"
    local memo_file=".selected_camera${GROUP:+-$GROUP}"

    if [ ! -d "$cameras_dir" ]; then
        print_error "Camera configs directory not found: $cameras_dir"
        exit 1
    fi

    # Check if CAMERA is already provided
    if [ -n "$CAMERA" ]; then
        if [ -d "$cameras_dir/$CAMERA" ]; then
            echo "$CAMERA"
            return 0
        else
            print_error "Provided CAMERA='$CAMERA' not found in $cameras_dir" >&2
            exit 1
        fi
    fi

    # Get list of cameras
    local cameras=($(ls "$cameras_dir" | sort))

    if [ ${#cameras[@]} -eq 0 ]; then
        print_error "No camera configs found in $cameras_dir"
        exit 1
    fi

    local selected_camera=""

    # Check if there's a previous selection
    if [ -f "$memo_file" ]; then
        local prev_camera=$(cat "$memo_file")
        if [ -n "$prev_camera" ] && [ -d "$cameras_dir/$prev_camera" ]; then
            echo "" >&2
            echo "Previously selected: $prev_camera" >&2
            read -p "Use this camera? [Y/n]: " use_prev >&2
            if [ -z "$use_prev" ] || [ "$use_prev" = "y" ] || [ "$use_prev" = "Y" ]; then
                selected_camera="$prev_camera"
                echo "$selected_camera"
                return 0
            fi
        fi
    fi

    # Try fzf first (best UX) - can be disabled with USE_FZF=0
    if [ "${USE_FZF:-1}" = "1" ] && command -v fzf >/dev/null 2>&1; then
        print_info "Select camera (type to filter in order, e.g., 't20' shows t20* cameras):" >&2
        selected_camera=$(printf '%s\n' "${cameras[@]}" | fzf \
            --height=~100% \
            --layout=reverse \
            --exact \
            --prompt="Camera: " \
            --header="Select camera configuration (${#cameras[@]} available) - type to filter" \
            --preview-window=hidden | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        # Reset and clear terminal after fzf
        tput sgr0 2>/dev/null || true
        clear
        echo "" >&2

    # Try whiptail (used by main Makefile)
    elif command -v whiptail >/dev/null 2>&1; then
        # Build menu items for whiptail
        local menu_items=()
        for camera in "${cameras[@]}"; do
            menu_items+=("$camera" "")
        done

        selected_camera=$(whiptail --title "Camera Selection" \
            --menu "Select a camera config (${#cameras[@]} available):" \
            20 76 12 \
            "${menu_items[@]}" \
            3>&1 1>&2 2>&3)

    # Try dialog as fallback
    elif command -v dialog >/dev/null 2>&1; then
        # Build menu items for dialog
        local menu_items=()
        for camera in "${cameras[@]}"; do
            menu_items+=("$camera" "")
        done

        selected_camera=$(dialog --stdout --title "Camera Selection" \
            --menu "Select a camera config (${#cameras[@]} available):" \
            20 76 12 \
            "${menu_items[@]}")

    # Fallback to numbered list
    else
        echo "" >&2
        echo "Available cameras (${#cameras[@]} total):" >&2
        echo "==========================================" >&2

        local i=1
        for camera in "${cameras[@]}"; do
            printf "%3d) %s\n" $i "$camera" >&2
            ((i++))
        done

        echo "" >&2
        read -p "Select camera number (1-${#cameras[@]}), or press Enter to cancel: " selection >&2

        if [ -z "$selection" ]; then
            print_info "Cancelled"
            exit 0
        fi

        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#cameras[@]} ]; then
            print_error "Invalid selection: $selection"
            exit 1
        fi

        selected_camera="${cameras[$((selection-1))]}"
    fi

    if [ -z "$selected_camera" ]; then
        exit 0
    fi

    # Strip any ANSI color codes that might have been captured
    selected_camera=$(echo "$selected_camera" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

    # Save selection for next time
    echo "$selected_camera" > "$memo_file"

    echo "$selected_camera"
}

# Parse command
CMD="${1:-build}"

case "$CMD" in
    shell)
        print_info "Starting interactive shell in container..."
        make -f Makefile.docker docker-shell CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    menuconfig|linux-menuconfig|busybox-menuconfig)
        print_info "Running $CMD in container..."
        make -f Makefile.docker "docker-$CMD" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    clean)
        print_info "Running clean build in container..."
        make -f Makefile.docker docker-clean-build CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    cleanbuild)
        # Select camera
        CAMERA=$(select_camera)

        # Strip any ANSI codes that might have been captured
        CAMERA=$(echo "$CAMERA" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        if [ -z "$CAMERA" ]; then
            print_error "No camera selected"
            exit 1
        fi

        print_success "Selected camera: $CAMERA"
        print_info "Running CLEAN build (distclean + fast parallel)..."

        # Build with selected camera using cleanbuild target
        make -f Makefile.docker docker-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} MAKECMDGOALS="cleanbuild" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    dev)
        # Select camera
        CAMERA=$(select_camera)

        # Strip any ANSI codes that might have been captured
        CAMERA=$(echo "$CAMERA" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        if [ -z "$CAMERA" ]; then
            print_error "No camera selected"
            exit 1
        fi

        print_success "Selected camera: $CAMERA"
        print_info "Running SERIAL build for debugging (incremental, stops at errors)..."

        # Build with selected camera using dev target (serial build with V=1)
        make -f Makefile.docker docker-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} MAKECMDGOALS="dev" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    upgrade_ota)
        # Select camera
        CAMERA=$(select_camera)

        # Strip any ANSI codes that might have been captured
        CAMERA=$(echo "$CAMERA" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        if [ -z "$CAMERA" ]; then
            print_error "No camera selected"
            exit 1
        fi

        print_success "Selected camera: $CAMERA"
        print_info "Running upgrade_ota in container..."

        # Build with selected camera
        make -f Makefile.docker docker-upgrade-ota CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} CONTAINER_ENGINE="$CONTAINER_ENGINE" "$@"
        ;;
    build|"")
        # Select camera
        CAMERA=$(select_camera)

        # Strip any ANSI codes that might have been captured
        CAMERA=$(echo "$CAMERA" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        if [ -z "$CAMERA" ]; then
            print_error "No camera selected"
            exit 1
        fi

        print_success "Selected camera: $CAMERA"
        print_info "Building firmware in container (parallel incremental)..."

        # Build with selected camera (uses default 'all' target which is incremental parallel)
        make -f Makefile.docker docker-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} MAKECMDGOALS="all" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    info)
        make -f Makefile.docker docker-info CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    images)
        print_info "Locating built firmware images..."
        if [ -d "output-stable" ]; then
            find output-stable -name "thingino-*.bin" -type f -exec ls -lh {} \;
        else
            print_error "No output-stable directory found. Have you built firmware yet?"
        fi
        ;;
    rebuild-image)
        print_info "Rebuilding container image..."
        make -f Makefile.docker docker-clean CONTAINER_ENGINE="$CONTAINER_ENGINE"
        make -f Makefile.docker docker-build CONTAINER_ENGINE="$CONTAINER_ENGINE"
        print_success "Container image rebuilt"
        ;;
    *)
        cat << 'EOF' >&2
Unknown command. Available commands:

  ./docker-build.sh              Build firmware (parallel incremental)
  ./docker-build.sh cleanbuild   Clean + build from scratch (parallel)
  ./docker-build.sh dev          Debug build (serial incremental, V=1, stops at errors)
  ./docker-build.sh shell        Interactive shell in container
  ./docker-build.sh menuconfig   Configure build options
  ./docker-build.sh clean        Clean build artifacts
  ./docker-build.sh info         Show container configuration
  ./docker-build.sh rebuild-image Rebuild the container image
  ./docker-build.sh upgrade_ota  Upgrade firmware OTA (requires IP=x.x.x.x)

EOF
        exit 1
        ;;
esac

exit 0
