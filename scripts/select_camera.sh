#!/bin/bash
#
# Camera selection script for Thingino firmware
# Supports fzf, whiptail, dialog, and numbered list fallback
#
# Usage: select_camera.sh <cameras_dir> <memo_file>
#
# Returns: Camera directory name (not full path)
#

cameras_dir="$1"
memo_file="$2"

if [ -z "$cameras_dir" ] || [ -z "$memo_file" ]; then
	echo "ERROR: Usage: $0 <cameras_dir> <memo_file>" >&2
	exit 1
fi

if [ ! -d "$cameras_dir" ]; then
	echo "ERROR: Camera configs directory not found: $cameras_dir" >&2
	exit 1
fi

# Get list of cameras (list subdirectories in cameras_dir)
cameras=($(ls "$cameras_dir" | sort))

if [ ${#cameras[@]} -eq 0 ]; then
	echo "ERROR: No camera configs found in $cameras_dir" >&2
	exit 1
fi

selected_camera=""

# Check if there's a previous selection
if [ -f "$memo_file" ]; then
	prev_camera=$(cat "$memo_file")
	if [ -n "$prev_camera" ] && [ -d "$cameras_dir/$prev_camera" ]; then
		echo "" >&2
		echo "Previously selected: $prev_camera" >&2
		read -p "Use this camera? [Y/n]: " use_prev >&2
		if [ -z "$use_prev" ] || [ "$use_prev" = "y" ] || [ "$use_prev" = "Y" ]; then
			selected_camera="$prev_camera"
			echo "$selected_camera"
			exit 0
		fi
	fi
fi

# Try fzf first (best UX) - can be disabled with USE_FZF=0
if [ "${USE_FZF:-1}" = "1" ] && command -v fzf >/dev/null 2>&1; then
	echo "Select camera (type to filter in order, e.g., 't20' shows t20* cameras):" >&2
	selected_camera=$(printf '%s\n' "${cameras[@]}" | fzf \
		--height=~100% \
		--layout=reverse \
		--exact \
		--prompt="Camera: " \
		--header="Select camera configuration (${#cameras[@]} available) - type to filter" \
		--preview-window=hidden | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')
	# Reset and clear terminal after fzf
	tput sgr0 2>/dev/null || true
	clear
	echo "" >&2

# Try whiptail (legacy compatibility)
elif command -v whiptail >/dev/null 2>&1; then
	menu_items=()
	for camera in "${cameras[@]}"; do
		menu_items+=("$camera" "")
	done
	selected_camera=$(whiptail --title "Camera Selection" \
		--menu "Select a camera config (${#cameras[@]} available):" \
		20 76 12 \
		"${menu_items[@]}" \
		3>&1 1>&2 2>&3)

# Try dialog as fallback
elif command -v dialog >/dev/null 2>&1; then
	menu_items=()
	for camera in "${cameras[@]}"; do
		menu_items+=("$camera" "")
	done
	selected_camera=$(dialog --stdout --title "Camera Selection" \
		--menu "Select a camera config (${#cameras[@]} available):" \
		20 76 12 \
		"${menu_items[@]}")

# Fallback to numbered list
else
	echo "" >&2
	echo "Available cameras (${#cameras[@]} total):" >&2
	echo "==========================================" >&2
	i=1
	for camera in "${cameras[@]}"; do
		printf "%3d) %s\n" $i "$camera" >&2
		((i++))
	done
	echo "" >&2
	read -p "Select camera number (1-${#cameras[@]}), or press Enter to cancel: " selection >&2
	if [ -z "$selection" ]; then
		echo "Cancelled" >&2
		exit 1
	fi
	if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#cameras[@]} ]; then
		echo "Invalid selection: $selection" >&2
		exit 1
	fi
	selected_camera="${cameras[$((selection-1))]}"
fi

if [ -z "$selected_camera" ]; then
	exit 1
fi

# Strip any ANSI color codes that might have been captured
selected_camera=$(echo "$selected_camera" | sed 's/\x1b[^a-zA-Z]*[a-zA-Z]//g')

# Save selection for next time
echo "$selected_camera" > "$memo_file"

# Output just the camera name
echo "$selected_camera"
