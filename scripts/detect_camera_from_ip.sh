#!/bin/bash
#
# Detect camera defconfig name by SSH-ing into a Thingino device
# and reading IMAGE_ID from /etc/os-release.
#
# Usage: detect_camera_from_ip.sh <ip_address>
# Returns: camera name on stdout (exit 0), or nothing (exit 1) on failure.
#

IP="$1"
if [ -z "$IP" ]; then
	echo "ERROR: IP address required" >&2
	exit 1
fi

SSH_OPTS="-T -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o PasswordAuthentication=yes -o LogLevel=ERROR"

# Capture stdout only; let SSH stderr (connection errors) pass through to terminal.
ssh_output=$(ssh $SSH_OPTS "root@$IP" \
	"grep '^IMAGE_ID=' /etc/os-release 2>/dev/null || grep '^IMAGE_ID=' /usr/lib/os-release 2>/dev/null")
ssh_exit=$?

if [ $ssh_exit -eq 255 ]; then
	echo "Warning: Could not connect to device at $IP" >&2
	exit 1
elif [ $ssh_exit -ne 0 ] || [ -z "$ssh_output" ]; then
	echo "Warning: Connected to $IP but no IMAGE_ID found (not a Thingino device?)" >&2
	exit 1
fi

REMOTE_IMAGE_ID=$(printf '%s' "$ssh_output" | cut -d'=' -f2 | tr -d '\n\r' | xargs)

if [ -z "$REMOTE_IMAGE_ID" ]; then
	echo "Warning: Connected to $IP but no IMAGE_ID found (not a Thingino device?)" >&2
	exit 1
fi

# Strip kernel version suffix if present on older firmware images
REMOTE_IMAGE_ID="${REMOTE_IMAGE_ID%-3.10}"
REMOTE_IMAGE_ID="${REMOTE_IMAGE_ID%-4.4}"

printf '%s\n' "$REMOTE_IMAGE_ID"
