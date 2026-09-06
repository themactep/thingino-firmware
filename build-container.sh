#!/bin/bash
# shellcheck disable=SC2001,SC2012,SC2034,SC2155,SC2162,SC2207
#
# Container wrapper for Thingino firmware build
# Provides non-interactive containerized build environment
#
# Usage:
#   ./build-container.sh            # Build firmware (fast parallel)
#   ./build-container.sh dev        # Debug build (slow serial, stops at errors)
#   ./build-container.sh menuconfig # Run menuconfig in container
#   ./build-container.sh shell      # Open interactive shell
#   ./build-container.sh clean      # Clean build in container
#   ./build-container.sh nuke       # Destroy all container images and dl cache
#   ./build-container.sh ota        # Upgrade firmware OTA
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

# Run Makefile.container without triggering host-side dep_check.sh from top-level Makefile
run_makefile_container() {
    WORKFLOW=1 make -f Makefile.container "$@"
}

# Minimum memory (MiB) for podman machine VM to avoid OOM during builds
PODMAN_MIN_MEMORY_MB=8192

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

# Ensure podman machine has enough memory (macOS/Windows only; Linux rootless has no VM)
if [ "$CONTAINER_ENGINE" = "podman" ] && podman machine list >/dev/null 2>&1; then
    PODMAN_MACHINE=$(podman machine list --format "{{.Name}}" 2>/dev/null | head -1)
    if [ -n "$PODMAN_MACHINE" ]; then
        CURRENT_MEM=$(podman machine inspect "$PODMAN_MACHINE" --format "{{.Resources.Memory}}" 2>/dev/null)
        if [ -n "$CURRENT_MEM" ] && [ "$CURRENT_MEM" -lt "$PODMAN_MIN_MEMORY_MB" ]; then
            print_info "Podman machine memory is ${CURRENT_MEM} MiB — increasing to ${PODMAN_MIN_MEMORY_MB} MiB to prevent OOM crashes..."
            if podman machine set --memory "$PODMAN_MIN_MEMORY_MB" "$PODMAN_MACHINE" 2>/dev/null; then
                print_success "Podman machine memory updated to ${PODMAN_MIN_MEMORY_MB} MiB"
            else
                print_error "Could not set podman machine memory automatically."
                echo "  Run manually: podman machine set --memory ${PODMAN_MIN_MEMORY_MB} ${PODMAN_MACHINE}"
            fi
        fi
    fi
fi

# Check for fresh container image
CONTAINER_IMAGE="ghcr.io/themactep/thingino-builder-image"
CONTAINER_TAG="latest"
case "$(uname -m)" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    *)       ARCH="$(uname -m)" ;;
esac

print_info "Checking for container image updates..."

# Get local digest
LOCAL_DIGEST=$($CONTAINER_ENGINE inspect "$CONTAINER_IMAGE:$CONTAINER_TAG" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//')

# Get remote digest for current platform
REMOTE_DIGEST=""
if command -v skopeo >/dev/null 2>&1; then
    REMOTE_DIGEST=$(skopeo inspect "docker://$CONTAINER_IMAGE:$CONTAINER_TAG" 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin).get('Digest',''))" 2>/dev/null)
elif [ "$CONTAINER_ENGINE" = "podman" ]; then
    REMOTE_DIGEST=$(podman manifest inspect "$CONTAINER_IMAGE:$CONTAINER_TAG" 2>/dev/null \
        | python3 -c "import sys,json; m=json.load(sys.stdin); print(next((x['digest'] for x in m.get('manifests',[]) if x.get('platform',{}).get('architecture')=='$ARCH'),''))" 2>/dev/null)
fi

if [ -z "$LOCAL_DIGEST" ]; then
    print_info "Pulling container image..."
    $CONTAINER_ENGINE pull "$CONTAINER_IMAGE:$CONTAINER_TAG"
    print_success "Pulled new container image"
elif [ -n "$REMOTE_DIGEST" ] && [ "$LOCAL_DIGEST" = "$REMOTE_DIGEST" ]; then
    print_info "Container image is current"
else
    print_info "Updating container image..."
    $CONTAINER_ENGINE pull "$CONTAINER_IMAGE:$CONTAINER_TAG"
    print_success "Updated container image"
fi

# Function to select camera
select_camera() {
    local cameras_dir="configs/cameras${GROUP:+-$GROUP}"
    local memo_file=".selected_camera${GROUP:+-$GROUP}"

    if [ ! -d "$cameras_dir" ]; then
        print_error "Camera configs directory not found: $cameras_dir"
        exit 1
    fi

    # Short-circuit when CAMERA is already provided
    if [ -n "$CAMERA" ]; then
        if [ -d "$cameras_dir/$CAMERA" ]; then
            echo "$CAMERA"
            return 0
        fi
        print_error "Provided CAMERA='$CAMERA' not found in $cameras_dir" >&2
        exit 1
    fi

    # Auto-detect a candidate from the device and offer it as the first suggestion
    local suggested_camera=""
    if [ -n "$IP" ]; then
        print_info "Probing device at $IP for camera identity..." >&2
        suggested_camera=$(scripts/detect_camera_from_ip.sh "$IP" 2>/dev/null) || true
        if [ -z "$suggested_camera" ] || [ ! -d "$cameras_dir/$suggested_camera" ]; then
            print_info "Could not identify device at $IP (not a Thingino device, or unreachable)" >&2
            suggested_camera=""
        fi
    fi

    local result
    result=$(scripts/select_camera.sh "$cameras_dir" "$memo_file" 0 "$suggested_camera") || true
    echo "$result"
}

# Parse command
CMD="${1:-build}"

case "$CMD" in
    shell)
        print_info "Starting interactive shell in container..."
        run_makefile_container container-shell CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    menuconfig|linux-menuconfig|busybox-menuconfig)
        print_info "Running $CMD in container..."
        run_makefile_container "container-$CMD" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    clean)
        print_info "Running clean build in container..."
        run_makefile_container container-clean-build CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    nuke)
        print_info "Destroying all container images and dl cache..."
        run_makefile_container container-nuke CONTAINER_ENGINE="$CONTAINER_ENGINE"
        print_success "All container artifacts removed"
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
        run_makefile_container container-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} ${IP:+IP="$IP"} MAKECMDGOALS="cleanbuild" CONTAINER_ENGINE="$CONTAINER_ENGINE"
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
        run_makefile_container container-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} ${IP:+IP="$IP"} MAKECMDGOALS="dev" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    ota)
        # Select camera
        CAMERA=$(select_camera)

        # Strip any ANSI codes that might have been captured
        CAMERA=$(echo "$CAMERA" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        if [ -z "$CAMERA" ]; then
            print_error "No camera selected"
            exit 1
        fi

        print_success "Selected camera: $CAMERA"
        print_info "Running ota in container..."

        # Build with selected camera
        run_makefile_container container-ota CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} ${IP:+IP="$IP"} CONTAINER_ENGINE="$CONTAINER_ENGINE" "$@"
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
        run_makefile_container container-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} ${IP:+IP="$IP"} MAKECMDGOALS="all" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
    info)
        run_makefile_container container-info CONTAINER_ENGINE="$CONTAINER_ENGINE"
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
        print_info "Pulling latest container image..."
        run_makefile_container container-pull CONTAINER_ENGINE="$CONTAINER_ENGINE"
        print_success "Container image updated"
        ;;
    *)
        # Select camera
        CAMERA=$(select_camera)

        # Strip any ANSI codes that might have been captured
        CAMERA=$(echo "$CAMERA" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

        if [ -z "$CAMERA" ]; then
            print_error "No camera selected"
            exit 1
        fi

        print_success "Selected camera: $CAMERA"
        print_info "Running '$*' in container..."

        # Pass all arguments through as make targets
        run_makefile_container container-make CAMERA="$CAMERA" ${GROUP:+GROUP="$GROUP"} ${IP:+IP="$IP"} MAKECMDGOALS="$*" CONTAINER_ENGINE="$CONTAINER_ENGINE"
        ;;
esac

exit 0
