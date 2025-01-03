#!/bin/bash

SSH_CONTROL_PATH="/tmp/ssh_mux_%h_%p_%r"
SSH_OPTS="-o ConnectTimeout=10 -o ServerAliveInterval=2 -o ControlMaster=auto -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=600 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Cleanup function to close SSH master connection
cleanup() {
	ssh -O exit $SSH_OPTS root@"$CAMERA_IP_ADDRESS" 2>/dev/null
}

# Trap to execute cleanup function on script exit
trap cleanup EXIT

# Downloads and installs the sysupgrade script
install_sysupgrade() {
	echo "Downloading and installing latest sysupgrade utility..."
	if ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
		curl -L https://raw.githubusercontent.com/themactep/thingino-firmware/refs/heads/master/package/thingino-sysupgrade/files/sysupgrade -o /usr/sbin/sysupgrade && \
		chmod +x /usr/sbin/sysupgrade"; then
		echo "Sysupgrade utility installed successfully."
	else
		echo "Failed to install sysupgrade utility."
	exit 1
	fi
}

# Validates input parameters and sets up SSH connection sharing, single authentication request
initialize_ssh_connection() {
	FIRMWARE_BIN="$1"
	CAMERA_IP_ADDRESS="$2"

	echo "Initializing SSH connection to device..."
	if ssh -fN $SSH_OPTS root@"$CAMERA_IP_ADDRESS"; then
		echo "SSH connection initialized."
	else
		echo "Failed to initialize ssh connection"
		exit 1
	fi
}

# Transfers firmware file and verifies SHA256 checksum
transfer_and_verify_firmware() {
	echo "Transferring firmware file to the device..."
	LOCAL_SHA256=$(sha256sum "$FIRMWARE_BIN" | cut -d' ' -f1)
	if timeout 300 ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "\
		cat >/tmp/fwupdate.bin; \
		REMOTE_SHA256=\$(sha256sum /tmp/fwupdate.bin | cut -d' ' -f1); \
		if [ \"\$REMOTE_SHA256\" != \"$LOCAL_SHA256\" ]; then \
			echo 'SHA256 checksum does not match, exiting...'; \
			exit 1; \
		fi" < "$FIRMWARE_BIN"; then
		echo "Firmware file transferred and SHA256 checksum verified."
	else
		echo "The firmware transfer process timed out or failed."
		exit 1
	fi
}

# Flashes the firmware to the specified device partition and reboots
flash_firmware() {
	if ssh $SSH_OPTS root@"$CAMERA_IP_ADDRESS" "sysupgrade -x /tmp/fwupdate.bin" 2>&1 | tee /dev/tty | grep -q "Rebooting"; then
		echo "Firmware flashed successfully. Device is rebooting."
	else
		echo "Firmware flashing failed."
		exit 1
	fi
}

main() {
	initialize_ssh_connection "$@"
	install_sysupgrade
	transfer_and_verify_firmware
	flash_firmware
}


if [ "$#" -ne 2 ]; then
	echo "Usage: $0 FIRMWARE_FILE IP_ADDRESS"
	exit 1
else
	main "$@"
fi
