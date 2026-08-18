#!/bin/bash
# shellcheck disable=SC2086,SC2029,SC2001
# SC2086: $SSH_OPTS is a space-separated list that must word-split.
#   $REMOTE_HOST is always set and contains no spaces or glob chars.
# SC2029: remote_run's $1 intentionally expands on the client side.
# SC2001: sed 's/M@.*//' clearer than ${var%%M@*} for rmem parsing.

die() {
	echo -e "\e[38;5;160m$1\e[0m" >&2
	exit 1
}

set -eu
# NOTE: no pipefail - the sysupgrade pipeline at line ~261 captures
# ${PIPESTATUS[0]} to check remote_run's exit code independently of
# tee; pipefail would kill the script before PIPESTATUS can be read.

FORCE=0
SKIP_SPACE_CHECK=0
MODE=full
DO_BACKUP=0
CAMERA_IP_ADDRESS=""
LOCAL_FW_FILE=""
TRIMMED_FILES=""
while getopts "fBnm:a:p:" opt; do
	case "$opt" in
		f) FORCE=1 ;;
		B) DO_BACKUP=1 ;;
		n) SKIP_SPACE_CHECK=1 ;;
		m) MODE="$OPTARG" ;;
		a) CAMERA_IP_ADDRESS="$OPTARG" ;;
		p) LOCAL_FW_FILE="$OPTARG" ;;
		*) die "Usage: $0 [-f] [-B] [-n] [-m full|kernel|boot|rootfs] [-a IP] [-p FIRMWARE_FILE]" ;;
	esac
done
shift $((OPTIND - 1))

case "$MODE" in
	full|kernel|boot|rootfs|all) ;;
	*) die "Invalid mode: $MODE (valid: all, full, kernel, boot, rootfs)" ;;
esac

# Normalize mode aliases
[ "$MODE" = "all" ] && MODE="full"

# Allow positional args as fallback: FIRMWARE_FILE IP_ADDRESS
[ -z "$LOCAL_FW_FILE" ] && [ "$#" -ge 1 ] && LOCAL_FW_FILE="$1" && shift
[ -z "$CAMERA_IP_ADDRESS" ] && [ "$#" -ge 1 ] && CAMERA_IP_ADDRESS="$1" && shift

[ -z "$LOCAL_FW_FILE" ] && die "No firmware file specified (-p or positional)"
[ -z "$CAMERA_IP_ADDRESS" ] && die "No IP address specified (-a or positional)"

cleanup() {
	if [ -n "${DEBUG:-}" ]; then
		ssh -O exit $SSH_OPTS $REMOTE_HOST 2>/dev/null
	fi
	printf '\033[0m' 2>/dev/null || true
}

remote_copy() {
	if [ -n "${DEBUG:-}" ]; then
		echo -e "\e[38;5;122mscp -O $SSH_OPTS $1 $2\e[0m" >&2
	fi
	scp -O $SSH_OPTS "$1" "$2"
}

remote_run() {
	if [ -n "${DEBUG:-}" ]; then
		echo -e "\e[38;5;118mssh $SSH_OPTS $1\e[0m" >&2
	fi
	ssh $SSH_OPTS $REMOTE_HOST "$1"
}

remote_uptime_seconds() {
	remote_run "awk '{print int(\$1)}' /proc/uptime" 2>/dev/null | tr -d '[:space:]'
}

select_remote_fw_path() {
	if remote_run "mountpoint -q /mnt/mmcblk0p1 && [ -w /mnt/mmcblk0p1 ]" >/dev/null 2>&1; then
		REMOTE_FW_FILE="/mnt/mmcblk0p1/fw.bin"
		echo "Using SD card staging area at /mnt/mmcblk0p1."
	else
		REMOTE_FW_FILE="/tmp/fw.bin"
	fi

	REMOTE_FW_DIR="${REMOTE_FW_FILE%/*}"
}

remote_mem_available_kb() {
	remote_run "awk '\$1==\"MemAvailable:\" { print int(\$2); found=1 } \$1==\"MemFree:\" && !memfree { memfree=int(\$2) } END { if (!found) print memfree }' /proc/meminfo" 2>/dev/null | tr -d '[:space:]'
}

is_integer() {
	case "$1" in
		''|*[!0-9]*)
			return 1
			;;
		*)
			return 0
			;;
	esac
}

prepare_upload_memory() {
	echo "Freeing memory before upload..."
	remote_run "rm -f /tmp/snapshot.jpg; rm -rf /tmp/sysupgrade /tmp/fw.bin; sync; if [ -x /etc/init.d/S31raptor ]; then /etc/init.d/S31raptor stop; elif [ -x /etc/init.d/S31prudynt ]; then /etc/init.d/S31prudynt stop; elif pidof prudynt >/dev/null 2>&1; then killall prudynt 2>/dev/null || true; fi; sleep 1; [ -w /proc/sys/vm/drop_caches ] && echo 3 > /proc/sys/vm/drop_caches || true" >/dev/null || \
		echo "Warning: failed to free memory before upload."
}

wait_for_reboot_after_detach() {
	local retries

	retries=120

	echo "Waiting for detached flash to reboot the device..."
	while [ "$retries" -gt 0 ]; do
		if remote_run "test ! -f /tmp/needs_reboot" 2>/dev/null; then
			echo "Device rebooted successfully (/tmp/needs_reboot is gone)."
			return 0
		fi

		retries=$(( retries - 1 ))
		sleep 2
	done

	return 1
}

check_and_free_space() {
	local fw_size_kb remote_avail_kb remote_memavail_kb dir_needed_kb mem_needed_kb
	fw_size_kb=$(( ($(stat -c%s "$UPLOAD_FW_FILE") + 1023) / 1024 ))
	# Uploading into tmpfs also needs extra RAM for dropbear/scp buffers and page cache.
	mem_needed_kb=$(( fw_size_kb + 8192 ))

	select_remote_fw_path
	prepare_upload_memory

	if [ "$REMOTE_FW_DIR" = "/tmp" ]; then
		# Need room for the firmware plus sysupgrade working files in /tmp.
		dir_needed_kb=$(( fw_size_kb + (fw_size_kb / 2) ))
	else
		# SD card staging does not require tmpfs working-space headroom.
		dir_needed_kb=$fw_size_kb
	fi

	remote_avail_kb=$(remote_run "df -k $REMOTE_FW_DIR | awk 'NR==2{print \$4}'" | tr -d '[:space:]')
	is_integer "$remote_avail_kb" || die "Failed to read available space in ${REMOTE_FW_DIR} on the device."
	echo "Firmware size: ${fw_size_kb}KB, available ${REMOTE_FW_DIR}: ${remote_avail_kb}KB, needed in ${REMOTE_FW_DIR}: ${dir_needed_kb}KB"

	if [ "$REMOTE_FW_DIR" != "/tmp" ]; then
		[ "$remote_avail_kb" -ge "$dir_needed_kb" ] && return 0
		die "Not enough free space in ${REMOTE_FW_DIR} on the device."
	fi

	remote_memavail_kb=$(remote_mem_available_kb)
	is_integer "$remote_memavail_kb" || die "Failed to read available RAM on the device."
	echo "Available RAM: ${remote_memavail_kb}KB, needed for upload: ${mem_needed_kb}KB"

	[ "$remote_avail_kb" -ge "$dir_needed_kb" ] && [ "$remote_memavail_kb" -ge "$mem_needed_kb" ] && return 0

	echo "Not enough upload headroom on the device. Attempting to free memory by remapping rmem..."

	local osmem rmem_val ispmem_val osmem_mb osmem_addr rmem_mb rmem_addr ispmem_mb ispmem_addr new_osmem_mb remap_cmd remap_msg
	osmem=$(remote_run "fw_printenv -n osmem" | tr -d '[:space:]')
	rmem_val=$(remote_run "fw_printenv -n rmem" | tr -d '[:space:]')
	ispmem_val=$(remote_run "fw_printenv -n ispmem 2>/dev/null" | tr -d '[:space:]')

	osmem_mb=$(echo "$osmem" | sed 's/M@.*//')
	osmem_addr=$(echo "$osmem" | sed 's/.*@//')
	rmem_mb=$(echo "$rmem_val" | sed 's/M@.*//')
	rmem_addr=$(echo "$rmem_val" | sed 's/.*@//')
	ispmem_mb=$(echo "$ispmem_val" | sed 's/M@.*//')
	ispmem_addr=$(echo "$ispmem_val" | sed 's/.*@//')

	if [ -z "$rmem_mb" ] || [ "$rmem_mb" -le 0 ]; then
		die "Not enough upload headroom and rmem is not set or already zero. Cannot proceed."
	fi

	new_osmem_mb=$(( osmem_mb + rmem_mb ))
	remap_cmd="fw_setenv rmem 0M@${rmem_addr}"
	remap_msg="rmem ${rmem_mb}M -> 0M (at ${rmem_addr})"

	# Some SoCs (t20/t10) also reserve ispmem between osmem and rmem; fold it into osmem too.
	if is_integer "$ispmem_mb" && [ "$ispmem_mb" -gt 0 ]; then
		new_osmem_mb=$(( new_osmem_mb + ispmem_mb ))
		remap_cmd="$remap_cmd && fw_setenv ispmem 0M@${ispmem_addr}"
		remap_msg="$remap_msg, ispmem ${ispmem_mb}M -> 0M (at ${ispmem_addr})"
	fi

	echo "Remapping memory: osmem ${osmem_mb}M -> ${new_osmem_mb}M, ${remap_msg}"

	# Plant a tmpfs marker to verify the camera actually reboots.
	# /tmp is on tmpfs and gets wiped on every reboot, so if the
	# marker is still present after we reconnect, the camera did
	# NOT reboot (e.g. shutdown stalled on a stuck init script).
	remote_run "touch /tmp/needs_reboot" || true

	remote_run "fw_setenv osmem ${new_osmem_mb}M@${osmem_addr} && $remap_cmd && reboot -f" || true

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

	echo "Device is back online. Verifying reboot..."
	if remote_run "test -f /tmp/needs_reboot" 2>/dev/null; then
		die "Device did NOT reboot after memory remap (/tmp/needs_reboot still exists). The camera may be stalled on shutdown. Aborting to prevent bricking."
	fi
	echo "Reboot confirmed (/tmp/needs_reboot is gone)."

	# Verify memory remap actually persisted across the reboot
	local actual_osmem
	actual_osmem=$(remote_run "fw_printenv -n osmem" | tr -d '[:space:]')
	if [ "$actual_osmem" != "${new_osmem_mb}M@${osmem_addr}" ]; then
		die "Memory remap did not persist across reboot: osmem=$actual_osmem expected=${new_osmem_mb}M@${osmem_addr}. Aborting."
	fi
	echo "Memory remap verified: osmem=$actual_osmem."

	echo "Re-initializing SSH mux..."
	ssh -fN $SSH_OPTS $REMOTE_HOST >/dev/null 2>/dev/null || die "Failed to re-initialize SSH connection after reboot"

	echo "Re-uploading sysupgrade utility (tmpfs was cleared on reboot)..."
	upload_sysupgrade
	select_remote_fw_path
	prepare_upload_memory

	remote_avail_kb=$(remote_run "df -k $REMOTE_FW_DIR | awk 'NR==2{print \$4}'" | tr -d '[:space:]')
	is_integer "$remote_avail_kb" || die "Failed to read available space in ${REMOTE_FW_DIR} after memory remap."
	echo "Post-remap available ${REMOTE_FW_DIR}: ${remote_avail_kb}KB"

	if [ "$REMOTE_FW_DIR" = "/tmp" ]; then
		remote_memavail_kb=$(remote_mem_available_kb)
		is_integer "$remote_memavail_kb" || die "Failed to read available RAM after memory remap."
		echo "Post-remap available RAM: ${remote_memavail_kb}KB"
		[ "$remote_avail_kb" -ge "$dir_needed_kb" ] && [ "$remote_memavail_kb" -ge "$mem_needed_kb" ] && return 0
		die "Not enough upload headroom after memory remap."
	fi

	[ "$remote_avail_kb" -ge "$dir_needed_kb" ] || die "Not enough free space in ${REMOTE_FW_DIR} after memory remap."
}

trap cleanup EXIT

LOCAL_SCRIPT="$(dirname "$0")/../package/thingino-sysupgrade/files/sysupgrade"
LOCAL_SCRIPT2="$(dirname "$0")/../package/thingino-sysupgrade/files/sysupgrade-stage2"
LOCAL_FLASH_OTA="$(dirname "$0")/../package/thingino-sysupgrade/files/flash-ota"

REMOTE_FW_FILE="/tmp/fw.bin"
REMOTE_FW_DIR="/tmp"
REMOTE_HOST="root@$CAMERA_IP_ADDRESS"
REMOTE_SCRIPT="/tmp/sup"

SSH_OPTS="-o ConnectTimeout=30 -o ServerAliveInterval=2 \
-o ServerAliveCountMax=30 \
-o ControlMaster=auto -o ControlPath=/tmp/ssh_mux_%h_%p_%r \
-o ControlPersist=600 -o StrictHostKeyChecking=no \
-o UserKnownHostsFile=/dev/null"

[ -n "${DEBUG:-}" ] && echo "Initializing SSH connection to $REMOTE_HOST..."
ssh -fN $SSH_OPTS $REMOTE_HOST >/dev/null 2>/dev/null || \
	die "Failed to initialize ssh connection"
echo "SSH connection initialized."

echo "Checking firmware compatibility..."
REMOTE_IMAGE_ID=$(remote_run "grep '^IMAGE_ID=' /etc/os-release | cut -d'=' -f2" | tr -d '\n')
REMOTE_IMAGE_ID="${REMOTE_IMAGE_ID%-3.10}"
REMOTE_IMAGE_ID="${REMOTE_IMAGE_ID%-4.4}"

# Prefer CAMERA from the Makefile; otherwise derive from the firmware
# filename (thingino-<camera>.bin) or the companion .md heading so direct
# script use works.
LOCAL_IMAGE_ID="${CAMERA:-}"
if [ -z "$LOCAL_IMAGE_ID" ] || [ "$LOCAL_IMAGE_ID" = "unknown" ]; then
	fw_base=$(basename "$LOCAL_FW_FILE" .bin)
	case "$fw_base" in
		thingino-*)
			LOCAL_IMAGE_ID="${fw_base#thingino-}"
			;;
		*)
			LOCAL_IMAGE_ID=
			;;
	esac
fi
if [ -z "$LOCAL_IMAGE_ID" ]; then
	md_file=$(dirname "$LOCAL_FW_FILE")/$(basename "$LOCAL_FW_FILE" .bin).md
	# Companion partition dump is often named <camera>.md next to thingino-<camera>.bin
	[ -f "$md_file" ] || md_file=$(dirname "$LOCAL_FW_FILE")/${REMOTE_IMAGE_ID}.md
	if [ -f "$md_file" ]; then
		LOCAL_IMAGE_ID=$(sed -n 's/^#[[:space:]]*//p' "$md_file" | head -n 1 | tr -d '\r')
	fi
fi
[ -n "$LOCAL_IMAGE_ID" ] || LOCAL_IMAGE_ID=unknown

if [ -z "$REMOTE_IMAGE_ID" ]; then
	die "Failed to read IMAGE_ID from device"
fi

if [ "$LOCAL_IMAGE_ID" != "$REMOTE_IMAGE_ID" ]; then
	if [ "$FORCE" -eq 1 ]; then
		echo "Warning: IMAGE_ID mismatch: local=$LOCAL_IMAGE_ID, device=$REMOTE_IMAGE_ID (forced)"
	else
		die "Firmware IMAGE_ID mismatch: local=$LOCAL_IMAGE_ID, device=$REMOTE_IMAGE_ID (use -f to override)"
	fi
fi

echo "Firmware compatibility verified."

free_overlay_space() {
	echo "Freeing overlay space on device..."
	remote_run "rm -rf /overlay/var /overlay/usr 2>/dev/null; mount -o remount / 2>/dev/null; echo done" >/dev/null || \
		echo "Warning: failed to free overlay space (non-fatal)"
}

upload_sysupgrade() {
	remote_copy "$LOCAL_SCRIPT" "$REMOTE_HOST:$REMOTE_SCRIPT" || \
		die "Failed to transfer sysupgrade utility"
	remote_copy "$LOCAL_SCRIPT2" "$REMOTE_HOST:/sbin/$(basename "$LOCAL_SCRIPT2")" || \
		die "Failed to transfer sysupgrade-stage2 utility"
	remote_run "chmod +x $REMOTE_SCRIPT" || \
		die "Failed to set execute permissions on sysupgrade utility"
	echo "Sysupgrade utility installed successfully."
}

upload_flash_ota() {
	remote_copy "$LOCAL_FLASH_OTA" "$REMOTE_HOST:/tmp/flash-ota.sh" || \
		die "Failed to transfer flash-ota"
	remote_run "chmod +x /tmp/flash-ota.sh" || \
		die "Failed to set execute permissions on flash-ota"
	echo "flash-ota utility installed."
}

free_overlay_space

if [ "$MODE" = "full" ]; then
	# Full firmware - use traditional sysupgrade
	echo "Transferring sysupgrade utility to device..."
	upload_sysupgrade

	UPLOAD_FW_FILE="$LOCAL_FW_FILE"

	if [ "$SKIP_SPACE_CHECK" -eq 1 ]; then
		echo "Skipping space/memory checks (-n)."
		select_remote_fw_path
		prepare_upload_memory
	else
		echo "Checking available space in /tmp on device..."
		check_and_free_space
	fi

	echo "Transferring firmware file to the device..."
	remote_copy "$UPLOAD_FW_FILE" "$REMOTE_HOST:$REMOTE_FW_FILE" || \
		die "The firmware transfer process timed out or failed."

	hash_l=$(sha256sum "$UPLOAD_FW_FILE" | cut -d' ' -f1)
	hash_r=$(remote_run "sha256sum $REMOTE_FW_FILE | cut -d' ' -f1")
	[ "$hash_l" != "$hash_r" ] && \
		die "SHA256 checksum does not match, exiting..."
	echo "Firmware file transferred and SHA256 checksum verified."

	remote_run "touch /tmp/needs_reboot" || true

	ota_log=$(mktemp)
	[ "$DO_BACKUP" -eq 1 ] && SUP_FLAG="-B" || SUP_FLAG=""

	remote_run "$REMOTE_SCRIPT -x $SUP_FLAG $REMOTE_FW_FILE" 2>&1 | tee /dev/tty | tee "$ota_log" >/dev/null
	ota_status=${PIPESTATUS[0]}

	if grep -q "Rebooting" "$ota_log"; then
		rm -f "$ota_log"
		echo "Firmware flashed successfully. Device is rebooting."
		exit 0
	fi

	if grep -q "Flash process running with PID" "$ota_log"; then
		if wait_for_reboot_after_detach; then
			rm -f "$ota_log"
			echo "Firmware flashed successfully. Device is rebooting."
			exit 0
		fi
		remote_log_tail=$(remote_run "tail -n 50 /tmp/sysupgrade-flash.log" 2>/dev/null) && echo "$remote_log_tail" >&2
		rm -f "$ota_log"
		die "Detached flash did not complete successfully"
	fi

	rm -f "$ota_log"
	[ "$ota_status" -ne 0 ] && die "Failed to flash firmware"
	die "Failed to flash firmware"
fi

# Boot / kernel / rootfs - use minimal flash-ota

echo "Transferring flash-ota utility to device..."
upload_flash_ota

# Assemble partition files and build the flash command
FLASH_CMD="/tmp/flash-ota.sh"
TRIMMED_FILES=""

if [ "$MODE" = "boot" ]; then
	IMAGES_DIR="$(dirname "$LOCAL_FW_FILE")"
	ENV_BIN="$IMAGES_DIR/u-boot-env.bin"

	# Boot partition: pad to 320 KB
	BOOT_TRIMMED="${LOCAL_FW_FILE}.boot"
	cp "$LOCAL_FW_FILE" "$BOOT_TRIMMED" || die "Failed to copy bootloader"
	truncate -s 327680 "$BOOT_TRIMMED" || die "Failed to pad bootloader"
	TRIMMED_FILES="$BOOT_TRIMMED"
	REMOTE_BOOT="/tmp/boot.bin"
	FLASH_CMD="$FLASH_CMD boot $REMOTE_BOOT"

	if [ -f "$ENV_BIN" ]; then
		ENV_TRIMMED="${LOCAL_FW_FILE}.env"
		cp "$ENV_BIN" "$ENV_TRIMMED" || die "Failed to copy env"
		truncate -s 65536 "$ENV_TRIMMED" || die "Failed to pad env"
		TRIMMED_FILES="$TRIMMED_FILES $ENV_TRIMMED"
		REMOTE_ENV="/tmp/env.bin"
		FLASH_CMD="$FLASH_CMD $REMOTE_ENV"
	fi

elif [ "$MODE" = "kernel" ]; then
	UPLOAD_FW_FILE="$LOCAL_FW_FILE"
	REMOTE_KERNEL="/tmp/kernel.bin"
	FLASH_CMD="$FLASH_CMD kernel $REMOTE_KERNEL"

elif [ "$MODE" = "rootfs" ]; then
	IMAGES_DIR="$(dirname "$LOCAL_FW_FILE")"
	DATA_BIN="$IMAGES_DIR/data.jffs2"
	[ ! -f "$DATA_BIN" ] && die "data.jffs2 not found alongside rootfs.squashfs"

	sqfs_size=$(stat -c%s "$LOCAL_FW_FILE")
	sqfs_aligned=$(( (sqfs_size + 65535) / 65536 * 65536 ))

	ROOTFS_TRIMMED="${LOCAL_FW_FILE}.rootfs"
	cp "$LOCAL_FW_FILE" "$ROOTFS_TRIMMED" || die "Failed to copy rootfs"
	truncate -s $sqfs_aligned "$ROOTFS_TRIMMED" || die "Failed to pad rootfs"
	TRIMMED_FILES="$ROOTFS_TRIMMED"
	REMOTE_ROOTFS="/tmp/rootfs.bin"
	FLASH_CMD="$FLASH_CMD rootfs $REMOTE_ROOTFS"

	DATA_TRIMMED="${LOCAL_FW_FILE}.data"
	cp "$DATA_BIN" "$DATA_TRIMMED" || die "Failed to copy data"
	TRIMMED_FILES="$TRIMMED_FILES $DATA_TRIMMED"
	REMOTE_DATA="/tmp/data.bin"
	FLASH_CMD="$FLASH_CMD $REMOTE_DATA"
fi

# Clean up trimmed files on exit
trap 'rm -f ${TRIMMED_FILES:-}; cleanup' EXIT

# Upload partition files
case "$MODE" in
	boot)
		echo "Uploading boot partition..."
		remote_copy "$BOOT_TRIMMED" "$REMOTE_HOST:$REMOTE_BOOT" || die "Failed to upload boot"
		if [ -n "$REMOTE_ENV" ]; then
			echo "Uploading env partition..."
			remote_copy "$ENV_TRIMMED" "$REMOTE_HOST:$REMOTE_ENV" || die "Failed to upload env"
		fi
		;;
	kernel)
		echo "Uploading kernel..."
		remote_copy "$LOCAL_FW_FILE" "$REMOTE_HOST:$REMOTE_KERNEL" || die "Failed to upload kernel"
		;;
	rootfs)
		echo "Uploading rootfs partition..."
		remote_copy "$ROOTFS_TRIMMED" "$REMOTE_HOST:$REMOTE_ROOTFS" || die "Failed to upload rootfs"
		echo "Uploading data partition..."
		remote_copy "$DATA_TRIMMED" "$REMOTE_HOST:$REMOTE_DATA" || die "Failed to upload data"
		;;
esac

echo "Partition files uploaded."

remote_run "touch /tmp/needs_reboot" || true

if [ "$DO_BACKUP" -eq 1 ] && [ "$MODE" = "rootfs" ]; then
	echo "Creating config backup on device..."
	remote_run "cfg-backup write" || echo "Warning: cfg-backup failed (non-fatal)"
fi

echo "Flashing..."
remote_run "$FLASH_CMD" || true

# flash-ota reboots the camera; SSH connection drops.
ssh -O exit $SSH_OPTS $REMOTE_HOST 2>/dev/null || true
echo "Done. Camera is rebooting."
