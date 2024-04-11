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
	if [ "$#" -ne 3 ]; then
		echo "Usage: $0 FIRMWARE_FILE IP_ADDRESS FLASH_PARTITION"
		exit 1
	fi

	FIRMWARE_BIN_NOBOOT="$1"
	CAMERA_IP_ADDRESS="$2"
	FLASH_PARTITION="$3"

	# Start the master connection & keep it open in the background
	ssh -fN $SSH_OPTS root@"$CAMERA_IP_ADDRESS"
	echo "SSH connection initialized."
}

# Checks if mtd5 and mtd6 are present in /proc/mtd on the camera
check_partitions_exist() {
	echo "Checking if required partitions (mtd5 and mtd6) exist..."
	ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
	if ! grep -q 'mtd5' /proc/mtd || ! grep -q 'mtd6' /proc/mtd; then \
			exit 1; \
	fi"

	# Check the exit status of the SSH command
	if [ "$?" -ne 0 ]; then
		echo "Required partitions not found. Exiting..."
		exit 1
	fi

	echo "Required partitions found."
}

# Transfers firmware file and verifies MD5 checksum
transfer_and_verify_firmware() {
	echo "Transferring firmware file to the device..."
	LOCAL_MD5=$(md5sum "$FIRMWARE_BIN_NOBOOT" | cut -d' ' -f1)

	ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
	cat >/tmp/fwupdate.bin; \
	REMOTE_MD5=\$(md5sum /tmp/fwupdate.bin | cut -d' ' -f1); \
	if [ \"\$REMOTE_MD5\" != \"$LOCAL_MD5\" ]; then \
			echo 'MD5 checksum does not match, exiting...'; \
			exit 1; \
	fi" < "$FIRMWARE_BIN_NOBOOT"
	echo "Firmware file transferred and MD5 checksum verified."
}

# Flashes the firmware to the specified device partition and reboots
flash_firmware() {
	echo "Flashing firmware to the device..."
	ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
	flashcp -v /tmp/fwupdate.bin /dev/${FLASH_PARTITION} && reboot;"
	echo "Firmware flashed successfully. Device is rebooting."
}

main() {
	initialize_ssh_connection "$@"
	check_partitions_exist
	transfer_and_verify_firmware
	flash_firmware
}

main "$@"
