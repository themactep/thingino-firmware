#!/bin/bash
# Standalone TFTP Server for Thingino Firmware Build Environment
# Serves compiled firmware images from output directories using Podman

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Default configuration
TFTP_PORT="${TFTP_PORT:-69}"
TFTP_ROOT="${TFTP_ROOT:-$PROJECT_DIR}"
TFTP_BIND="${TFTP_BIND:-0.0.0.0}"
TFTP_VERBOSE="${TFTP_VERBOSE:-1}"

# Container configuration
CONTAINER_NAME="thingino-tftpd"
CONTAINER_IMAGE="${TFTP_CONTAINER_IMAGE:-docker.io/pghalliday/tftp:latest}"

# State file (replaces PID file)
STATE_FILE="/tmp/thingino-tftpd.state"

show_help() {
    cat << EOF
Thingino TFTP Server - Serve compiled firmware images (Podman/Docker)

Usage: $0 [command] [options]

Commands:
    start       Start the TFTP server (default)
    stop        Stop the TFTP server
    restart     Restart the TFTP server
    status      Show server status
    logs        Show server logs
    help        Show this help message

Options:
    -p PORT     TFTP port (default: 69)
    -r ROOT     TFTP root directory (default: project root)
    -b BIND     Bind address (default: 0.0.0.0)
    -v          Verbose mode

Environment Variables:
    TFTP_PORT              Override default port
    TFTP_ROOT              Override root directory
    TFTP_BIND              Override bind address
    TFTP_VERBOSE           Override verbosity (0 or 1)
    TFTP_CONTAINER_IMAGE   Container image (default: docker.io/pghalliday/tftp:latest)

Examples:
    # Start server on default port 69 (may require sudo for podman)
    $0 start

    # Start on alternative port (no sudo needed for port > 1024)
    TFTP_PORT=6969 $0 start

    # Stop the server
    $0 stop

    # Check status
    $0 status

    # View logs
    $0 logs

Notes:
    - Uses Podman (or Docker) for platform independence
    - Port 69 may require root/sudo depending on system configuration
    - Use ports > 1024 for unprivileged operation
    - Server serves files from project root by default
    - Compiled images are in output-*/ directories
    - Container runs in background (detached mode)

EOF
}

check_dependencies() {
    # Check for podman or docker
    if command -v podman &> /dev/null; then
        CONTAINER_CMD="podman"
    elif command -v docker &> /dev/null; then
        CONTAINER_CMD="docker"
    else
        echo "Error: Neither Podman nor Docker is installed" >&2
        echo "" >&2
        echo "Install Podman (recommended):" >&2
        echo "  Ubuntu/Debian: sudo apt-get install podman" >&2
        echo "  Fedora/RHEL:   sudo dnf install podman" >&2
        echo "  Arch Linux:    sudo pacman -S podman" >&2
        echo "" >&2
        echo "Or install Docker:" >&2
        echo "  https://docs.docker.com/engine/install/" >&2
        return 1
    fi
    
    return 0
}

start_server() {
    # Check if container is already running
    if $CONTAINER_CMD ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "TFTP server container is already running"
        return 1
    fi
    
    # Remove existing stopped container if present
    if $CONTAINER_CMD ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "Removing old container..."
        $CONTAINER_CMD rm -f "$CONTAINER_NAME" &>/dev/null || true
    fi
    
    if ! check_dependencies; then
        return 1
    fi
    
    echo "Starting Thingino TFTP Server (Container)..."
    echo "  Runtime:    $CONTAINER_CMD"
    echo "  Image:      $CONTAINER_IMAGE"
    echo "  Root:       $TFTP_ROOT"
    echo "  Bind:       $TFTP_BIND"
    echo "  Port:       $TFTP_PORT"
    
    # Pull image if not present
    if ! $CONTAINER_CMD image exists "$CONTAINER_IMAGE" 2>/dev/null; then
        echo "Pulling container image..."
        $CONTAINER_CMD pull "$CONTAINER_IMAGE" || {
            echo "Error: Failed to pull container image" >&2
            return 1
        }
    fi
    
    # Start container
    local container_id
    container_id=$($CONTAINER_CMD run -d \
        --name "$CONTAINER_NAME" \
        -p "0.0.0.0:${TFTP_PORT}:69/udp" \
        -v "${TFTP_ROOT}:/var/tftpboot:ro" \
        "$CONTAINER_IMAGE" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to start container" >&2
        echo "$container_id" >&2
        
        # Check for common issues
        if echo "$container_id" | grep -q "permission denied\|EPERM\|Operation not permitted"; then
            echo "" >&2
            echo "Permission error detected. Try:" >&2
            if [ "$TFTP_PORT" -eq 69 ]; then
                echo "  Port 69 requires rootful podman/docker." >&2
                echo "  The Makefile should handle this automatically with sudo." >&2
                echo "  If running script directly: sudo $0 start" >&2
            fi
        fi
        return 1
    fi
    
    # Save state
    echo "$container_id" > "$STATE_FILE"
    
    sleep 2
    
    # Verify container is running
    if $CONTAINER_CMD ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo ""
        echo "✅ TFTP server started successfully!"
        echo "  Container:  $CONTAINER_NAME"
        echo "  ID:         $(echo $container_id | cut -c1-12)"
        echo "  Port:       $TFTP_PORT/udp"
        echo ""
        echo "Firmware images served from: $TFTP_ROOT"
        echo "From camera U-Boot: tftp 0x80600000 thingino-<camera>.bin"
        echo ""
        echo "Use '$0 logs' to view server logs"
        echo "Use '$0 status' for detailed status"
        return 0
    else
        echo "❌ Error: Container started but is not running" >&2
        echo "Run '$0 logs' to see what went wrong" >&2
        rm -f "$STATE_FILE"
        return 1
    fi
}

stop_server() {
    if ! check_dependencies; then
        return 1
    fi
    
    # Check if container is running
    if ! $CONTAINER_CMD ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "TFTP server container is not running"
        rm -f "$STATE_FILE"
        return 1
    fi
    
    echo "Stopping TFTP server container..."
    $CONTAINER_CMD stop "$CONTAINER_NAME" &>/dev/null
    
    echo "Removing container..."
    $CONTAINER_CMD rm "$CONTAINER_NAME" &>/dev/null
    
    rm -f "$STATE_FILE"
    echo "TFTP server stopped"
}

status_server() {
    if ! check_dependencies; then
        return 1
    fi
    
    # Check if container exists
    if ! $CONTAINER_CMD ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "TFTP server container is not running"
        rm -f "$STATE_FILE"
        return 1
    fi
    
    # Get container status
    local status=$($CONTAINER_CMD ps -a --filter "name=$CONTAINER_NAME" --format "{{.Status}}")
    local container_id=$($CONTAINER_CMD ps -a --filter "name=$CONTAINER_NAME" --format "{{.ID}}")
    
    echo "TFTP Server Status:"
    echo "  Container:  $CONTAINER_NAME"
    echo "  ID:         $container_id"
    echo "  Status:     $status"
    echo "  Image:      $CONTAINER_IMAGE"
    echo ""
    
    # If running, show additional details
    if $CONTAINER_CMD ps --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "  Root:       $TFTP_ROOT"
        echo "  Bind:       $TFTP_BIND:$TFTP_PORT -> 69/udp"
        echo ""
        echo "Container Details:"
        $CONTAINER_CMD inspect "$CONTAINER_NAME" --format '  Created:    {{.Created}}' 2>/dev/null || true
        $CONTAINER_CMD inspect "$CONTAINER_NAME" --format '  Started:    {{.State.StartedAt}}' 2>/dev/null || true
        echo ""
        echo "Port Mappings:"
        $CONTAINER_CMD port "$CONTAINER_NAME" 2>/dev/null || echo "  (none)"
        return 0
    else
        echo "Container exists but is not running"
        return 1
    fi
}

show_logs() {
    if ! check_dependencies; then
        return 1
    fi
    
    # Check if container exists
    if ! $CONTAINER_CMD ps -a --filter "name=$CONTAINER_NAME" --format "{{.Names}}" 2>/dev/null | grep -q "^${CONTAINER_NAME}$"; then
        echo "TFTP server container does not exist"
        return 1
    fi
    
    echo "TFTP Server Logs (last 50 lines):"
    echo "=================================="
    $CONTAINER_CMD logs --tail 50 "$CONTAINER_NAME"
}

# Parse command line arguments
COMMAND="${1:-start}"

case "$COMMAND" in
    start|stop|restart|status|logs|help)
        shift
        ;;
    *)
        # If first arg is an option, default to start
        if [[ "$COMMAND" == -* ]]; then
            COMMAND="start"
        else
            echo "Unknown command: $COMMAND" >&2
            show_help
            exit 1
        fi
        ;;
esac

# Parse options
while getopts "p:r:b:vh" opt; do
    case $opt in
        p) TFTP_PORT="$OPTARG" ;;
        r) TFTP_ROOT="$OPTARG" ;;
        b) TFTP_BIND="$OPTARG" ;;
        v) TFTP_VERBOSE=1 ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Execute command
case "$COMMAND" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server || true
        sleep 1
        start_server
        ;;
    status)
        status_server
        ;;
    logs)
        show_logs
        ;;
    help)
        show_help
        ;;
esac
