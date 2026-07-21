#!/bin/bash
#
# Backup /overlay from a Thingino camera to a local tarball.
#
# Usage: backup_overlay.sh <ip_address> <backup_dir>
#
# Detects the camera image name from IMAGE_ID in /etc/os-release.
# The tarball is named <camera_image_name>-<ip_address>.tar.gz
#

die() { echo -e "\e[38;5;160m$1\e[0m" >&2; exit 1; }

set -o pipefail

[ "$#" -ne 2 ] && die "Usage: $0 <ip_address> <backup_dir>"

IP_ADDRESS="$1"
BACKUP_DIR="$2"
REMOTE_HOST="root@$IP_ADDRESS"

SSH_OPTS="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

# Step 1: Get camera image name
echo "Connecting to camera at $IP_ADDRESS..."
IMAGE_ID=$(ssh $SSH_OPTS "$REMOTE_HOST" \
	"grep '^IMAGE_ID=' /etc/os-release 2>/dev/null || grep '^IMAGE_ID=' /usr/lib/os-release 2>/dev/null" 2>/dev/null)

if [ -z "$IMAGE_ID" ]; then
	die "Failed to retrieve IMAGE_ID from device at $IP_ADDRESS"
fi

CAMERA_NAME=$(printf '%s' "$IMAGE_ID" | cut -d'=' -f2 | tr -d '\n\r' | xargs)
# Strip kernel version suffix if present on older firmware images
CAMERA_NAME="${CAMERA_NAME%-3.10}"
CAMERA_NAME="${CAMERA_NAME%-4.4}"

if [ -z "$CAMERA_NAME" ]; then
	die "Failed to parse camera name from IMAGE_ID"
fi

echo "Camera image name: $CAMERA_NAME"

# Step 2: Build output filename
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
IP_SAFE=$(printf '%s' "$IP_ADDRESS" | tr '.' '-')
TARBALL_NAME="${CAMERA_NAME}-${IP_SAFE}-${TIMESTAMP}.tar.gz"
TARBALL_PATH="$BACKUP_DIR/$TARBALL_NAME"

mkdir -p "$BACKUP_DIR"

# Step 3: Stream overlay tarball directly from camera via SSH.
# The camera-side tar runs as root and can read files regardless of
# local permissions (e.g. crond.reboot with mode 000).
echo "Backing up /overlay/ from camera..."
if ! ssh $SSH_OPTS "$REMOTE_HOST" \
	"tar -cf - -C /overlay . 2>/dev/null | gzip -9" > "$TARBALL_PATH" 2>/dev/null; then
	rm -f "$TARBALL_PATH"
	die "Failed to stream /overlay from device"
fi

# Step 4: Verify the tarball
if [ ! -s "$TARBALL_PATH" ]; then
	rm -f "$TARBALL_PATH"
	die "Backup tarball is empty — /overlay may be inaccessible on the device"
fi

if ! gzip -t "$TARBALL_PATH" 2>/dev/null; then
	rm -f "$TARBALL_PATH"
	die "Backup tarball is corrupt"
fi

echo "Backup saved to: $TARBALL_PATH"
echo "Size: $(du -h "$TARBALL_PATH" | cut -f1)"
