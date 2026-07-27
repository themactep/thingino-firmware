#!/bin/bash

die() { echo -e "\e[38;5;160m$1\e[0m" >&2; exit 1; }

[ "$#" -ne 2 ] && die "Usage: $0 FIRMWARE_FILE IP_ADDRESS"

cleanup() {
	ssh -O exit $SSH_OPTS $REMOTE_HOST 2>/dev/null;
}

remote_copy() {
	echo -e "\e[38;5;122mscp -O $SSH_OPTS $1 $2\e[0m" >&2
	scp -O $SSH_OPTS "$1" "$2"
}

remote_run() {
	echo -e "\e[38;5;118mssh $SSH_OPTS $1\e[0m" >&2
	ssh $SSH_OPTS $REMOTE_HOST "$1"
}

trap cleanup EXIT

CAMERA_IP_ADDRESS="$2"

LOCAL_FW_FILE="$1"
LOCAL_SCRIPT="$(dirname "$0")/../package/thingino-sysupgrade/files/sysupgrade"

REMOTE_FW_FILE="/tmp/fw.bin"
REMOTE_HOST="root@$CAMERA_IP_ADDRESS"
REMOTE_SCRIPT="/tmp/sup"

SSH_OPTS="-o ConnectTimeout=30 -o ServerAliveInterval=2 \
-o ControlMaster=auto -o ControlPath=/tmp/ssh_mux_%h_%p_%r \
-o ControlPersist=600 -o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null"

echo "Initializing SSH connection to $REMOTE_HOST..."
ssh -fN $SSH_OPTS $REMOTE_HOST || \
	die "Failed to initialize ssh connection"

echo "SSH connection initialized."

remote_run "touch /tmp/webupgrade" || \
	die "Failed to create webupgrade flag"

echo "Transferring sysupgrade utility to device..."
remote_copy $LOCAL_SCRIPT $REMOTE_HOST:$REMOTE_SCRIPT || \
	die "Failed to transfer sysupgrade utility"

remote_run "chmod +x $REMOTE_SCRIPT" || \
	die "Failed to set execute permissions on sysupgrade utility"

echo "Sysupgrade utility installed successfully."

echo "Transferring firmware file to the device..."
remote_copy $LOCAL_FW_FILE $REMOTE_HOST:$REMOTE_FW_FILE || \
	die "The firmware transfer process timed out or failed."

hash_l=$(sha256sum "$LOCAL_FW_FILE" | cut -d' ' -f1)
hash_r=$(remote_run "sha256sum $REMOTE_FW_FILE | cut -d' ' -f1")
[ "$hash_l" != "$hash_r" ] && \
	die "SHA256 checksum does not match, exiting..."

echo "Firmware file transferred and SHA256 checksum verified."

remote_run "$REMOTE_SCRIPT -x $REMOTE_FW_FILE" 2>&1 | tee /dev/tty | grep -q "Rebooting" || \
	die "Failed to flash firmware"

echo "Firmware flashed successfully. Device is rebooting."

exit 0
