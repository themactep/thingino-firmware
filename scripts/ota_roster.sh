#!/bin/bash
# Build (if needed) and OTA-upgrade all cameras listed in user/camera_roster.csv

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROSTER_FILE="${ROSTER_FILE:-$ROOT_DIR/user/camera_roster.csv}"
MAKE_BIN="${MAKE:-make}"

log() { echo -e "$*" >&2; }
err() { echo -e "\e[38;5;160mERROR: $*\e[0m" >&2; }

trim() {
	local s="$1"
	# shellcheck disable=SC2001
	echo "$(echo "$s" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
}

get_output_dir() {
	local camera="$1"
	local group="$2"
	local out
	if [ -n "$group" ]; then
		out=$($MAKE_BIN -s --no-print-directory CAMERA="$camera" GROUP="$group" show-vars | awk -F'= ' '/^OUTPUT_DIR/{print $2; exit}')
	else
		out=$($MAKE_BIN -s --no-print-directory CAMERA="$camera" show-vars | awk -F'= ' '/^OUTPUT_DIR/{print $2; exit}')
	fi
	echo "$out"
}

needs_build() {
	local camera="$1"
	local group="$2"
	if [ -n "$group" ]; then
		$MAKE_BIN -q --no-print-directory CAMERA="$camera" GROUP="$group" pack >/dev/null 2>&1
	else
		$MAKE_BIN -q --no-print-directory CAMERA="$camera" pack >/dev/null 2>&1
	fi
	return $?
}

build_and_pack() {
	local camera="$1"
	local group="$2"
	if [ -n "$group" ]; then
		$MAKE_BIN --no-print-directory CAMERA="$camera" GROUP="$group" build_fast pack
	else
		$MAKE_BIN --no-print-directory CAMERA="$camera" build_fast pack
	fi
}

ota_upgrade() {
	local camera="$1"
	local ip="$2"
	local fw="$3"
	CAMERA="$camera" "$ROOT_DIR/scripts/fw_ota.sh" "$fw" "$ip"
}

if [ ! -f "$ROSTER_FILE" ]; then
	err "Roster file not found: $ROSTER_FILE"
	exit 1
fi

log "Using roster: $ROSTER_FILE"

failures=()
count=0

while IFS=, read -r col1 col2 col3 col4; do
	line="$col1$col2$col3$col4"
	# Skip blank or comment lines
	if [ -z "$(trim "$line")" ] || [[ "$(trim "$col1")" == \#* ]]; then
		continue
	fi

	name="$(trim "$col1")"
	ip="$(trim "$col2")"
	camera="$(trim "$col3")"
	group="$(trim "$col4")"

	# Skip header
	if [ "$name" = "name" ] && [ "$ip" = "ip" ] && [ "$camera" = "camera" ]; then
		continue
	fi

	# Allow 2-column format: camera,ip
	if [ -z "$camera" ] && [ -n "$name" ] && [ -n "$ip" ]; then
		camera="$name"
		name="$camera"
	fi

	if [ -z "$camera" ] || [ -z "$ip" ]; then
		err "Invalid roster row (expected name,ip,camera[,group]): $col1,$col2,$col3,$col4"
		failures+=("$name")
		continue
	fi

	count=$((count + 1))
	label="$name"
	[ -z "$label" ] && label="$camera"

	log ""
	log "===== $label ($camera @ $ip) ====="

	needs_build "$camera" "$group"
	case $? in
		0)
			log "✓ Firmware is fresh; reusing existing image."
			;;
		1)
			log "Building firmware..."
			if ! build_and_pack "$camera" "$group"; then
				err "Build failed for $label"
				failures+=("$label")
				continue
			fi
			;;
		2)
			err "Build check failed for $label"
			failures+=("$label")
			continue
			;;
	esac

	output_dir="$(get_output_dir "$camera" "$group")"
	if [ -z "$output_dir" ]; then
		err "Failed to resolve OUTPUT_DIR for $label"
		failures+=("$label")
		continue
	fi

	fw_path="$output_dir/images/thingino-$camera.bin"
	if [ ! -f "$fw_path" ]; then
		err "Firmware not found: $fw_path"
		failures+=("$label")
		continue
	fi

	log "OTA upgrade using: $fw_path"
	if ! ota_upgrade "$camera" "$ip" "$fw_path"; then
		err "OTA failed for $label"
		failures+=("$label")
		continue
	fi

done < "$ROSTER_FILE"

log ""
log "Processed $count device(s)."

if [ ${#failures[@]} -gt 0 ]; then
	err "Failures: ${failures[*]}"
	exit 1
fi

log "All devices upgraded successfully."
exit 0
