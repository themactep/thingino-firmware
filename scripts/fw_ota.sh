#!/bin/bash

SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"
SSH_OPTS="-o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=600 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Cleanup function to close SSH master connection
cleanup() {
	ssh -O exit $SSH_OPTS root@"$CAMERA_IP_ADDRESS" 2>/dev/null
	echo "SSH connection closed."
}

# Trap to execute cleanup function on script exit
trap cleanup EXIT

# Validates input parameters and sets up SSH connection sharing, single authentication request
initialize_ssh_connection() {
	if [ "$#" -ne 2 ]; then
		echo "Usage: $0 FIRMWARE_FILE IP_ADDRESS"
		exit 1
	fi

	FIRMWARE_BIN="$1"
	CAMERA_IP_ADDRESS="$2"

	echo "Initializing SSH connection to device..."
	ssh -fN $SSH_OPTS root@"$CAMERA_IP_ADDRESS"
	echo "SSH connection initialized."
}

# Transfers firmware file and verifies MD5 checksum
transfer_and_verify_firmware() {
	echo "Transferring firmware file to the device..."
	LOCAL_MD5=$(md5sum "$FIRMWARE_BIN" | cut -d' ' -f1)

	ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
	cat >/tmp/fwupdate.bin; \
	REMOTE_MD5=\$(md5sum /tmp/fwupdate.bin | cut -d' ' -f1); \
	if [ \"\$REMOTE_MD5\" != \"$LOCAL_MD5\" ]; then \
		echo 'MD5 checksum does not match, exiting...'; \
		exit 1; \
	fi" < "$FIRMWARE_BIN"
	echo "Firmware file transferred and MD5 checksum verified."
}

# Flashes the firmware to the specified device partition and reboots
flash_firmware() {
	ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
	sysupgrade /tmp/fwupdate.bin"
	echo "Firmware flashed successfully. Device is rebooting."
}

main() {
	initialize_ssh_connection "$@"
	transfer_and_verify_firmware
	flash_firmware
}

main "$@"
