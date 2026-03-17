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

check_and_free_space() {
	local fw_size_kb remote_avail_kb needed_kb
	fw_size_kb=$(( ($(stat -c%s "$LOCAL_FW_FILE") + 1023) / 1024 ))
	# MemAvailable was added in kernel 3.14; on 3.10 approximate with MemFree+Buffers+Cached
	remote_avail_kb=$(remote_run "awk '/^MemAvailable:/{a=\$2} /^MemFree:/{f=\$2} /^Buffers:/{b=\$2} /^Cached:/{c=\$2} END{print (a ? a : f+b+c)}' /proc/meminfo" | tr -d '[:space:]')
	# Require firmware size + 4MB headroom so the system keeps running during transfer
	needed_kb=$(( fw_size_kb + 4096 ))
	echo "Firmware size: ${fw_size_kb}KB, available RAM: ${remote_avail_kb}KB, needed: ${needed_kb}KB"

	[ "$remote_avail_kb" -ge "$needed_kb" ] && return 0

	echo "Not enough free RAM (need ${needed_kb}KB, have ${remote_avail_kb}KB). Attempting to free memory by remapping rmem..."

	local osmem rmem_val osmem_mb osmem_addr rmem_mb rmem_addr new_osmem_mb
	osmem=$(remote_run "fw_printenv -n osmem" | tr -d '[:space:]')
	rmem_val=$(remote_run "fw_printenv -n rmem" | tr -d '[:space:]')

	osmem_mb=$(echo "$osmem" | sed 's/M@.*//')
	osmem_addr=$(echo "$osmem" | sed 's/.*@//')
	rmem_mb=$(echo "$rmem_val" | sed 's/M@.*//')
	rmem_addr=$(echo "$rmem_val" | sed 's/.*@//')

	if [ -z "$rmem_mb" ] || [ "$rmem_mb" -le 0 ]; then
		die "Not enough space in /tmp and rmem is not set or already zero. Cannot proceed."
	fi

	new_osmem_mb=$(( osmem_mb + rmem_mb ))
	echo "Remapping memory: osmem ${osmem_mb}M -> ${new_osmem_mb}M, rmem ${rmem_mb}M -> 0M (at ${rmem_addr})"

	remote_run "fw_setenv osmem ${new_osmem_mb}M@${osmem_addr} && fw_setenv rmem 0M@${rmem_addr} && reboot" || true

	echo "Closing SSH mux..."
	ssh -O exit $SSH_OPTS $REMOTE_HOST 2>/dev/null || true

	echo "Waiting for device to reboot..."
	sleep 15

	local retries=30
	while [ "$retries" -gt 0 ]; do
		if ssh $SSH_OPTS -o ConnectTimeout=5 $REMOTE_HOST "echo ok" >/dev/null 2>&1; then
			break
		fi
		retries=$(( retries - 1 ))
		sleep 3
	done
	[ "$retries" -eq 0 ] && die "Device did not come back online after memory remap reboot."

	echo "Device is back online with remapped memory. Re-initializing SSH mux..."
	ssh -fN $SSH_OPTS $REMOTE_HOST || die "Failed to re-initialize SSH connection after reboot"

	echo "Re-uploading sysupgrade utility (tmpfs was cleared on reboot)..."
	upload_sysupgrade
}

trap cleanup EXIT

CAMERA_IP_ADDRESS="$2"

LOCAL_FW_FILE="$1"
LOCAL_SCRIPT="$(dirname "$0")/../package/thingino-sysupgrade/files/sysupgrade"
LOCAL_SCRIPT2="$(dirname "$0")/../package/thingino-sysupgrade/files/sysupgrade-stage2"

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

echo "Checking firmware compatibility..."
REMOTE_IMAGE_ID=$(remote_run "grep '^IMAGE_ID=' /etc/os-release | cut -d'=' -f2" | tr -d '\n')
REMOTE_IMAGE_ID="${REMOTE_IMAGE_ID%-3.10}"
REMOTE_IMAGE_ID="${REMOTE_IMAGE_ID%-4.4}"

# IMAGE_ID is derived from CAMERA variable which should be set by the Makefile
LOCAL_IMAGE_ID="${CAMERA:-unknown}"

if [ -z "$REMOTE_IMAGE_ID" ]; then
	die "Failed to read IMAGE_ID from device"
fi

if [ "$LOCAL_IMAGE_ID" != "$REMOTE_IMAGE_ID" ]; then
	die "Firmware IMAGE_ID mismatch: local=$LOCAL_IMAGE_ID, device=$REMOTE_IMAGE_ID"
fi

echo "Firmware compatibility verified."

upload_sysupgrade() {
	remote_copy $LOCAL_SCRIPT $REMOTE_HOST:$REMOTE_SCRIPT || \
		die "Failed to transfer sysupgrade utility"
	remote_copy $LOCAL_SCRIPT2 $REMOTE_HOST:/sbin/$(basename $LOCAL_SCRIPT2) || \
		die "Failed to transfer sysupgrade-stage2 utility"
	remote_run "chmod +x $REMOTE_SCRIPT" || \
		die "Failed to set execute permissions on sysupgrade utility"
	echo "Sysupgrade utility installed successfully."
}

echo "Transferring sysupgrade utility to device..."
upload_sysupgrade

echo "Checking available space in /tmp on device..."
check_and_free_space

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
