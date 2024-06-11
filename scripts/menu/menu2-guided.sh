#!/bin/bash

camera_value=""
step1_completed=false
step2_completed=false
step3_completed=false

source ./scripts/menu/menu-common.sh

main_menu() {
	local default_item="1"
	local step1_label="Step 1: Install prerequisites"

	while true; do
		# Adjust default item based on the state of the previous steps
		if [ -f ".prereqs.done" ]; then
			step1_completed=true
		fi

		if $step1_completed && $step2_completed; then
			default_item="3"  # Skip to Step 3 if step 1 and step 2 are completed
		elif $step1_completed; then
			default_item="2"  # Skip to Step 2 if step 1 is completed
		else
			default_item="1"  # Start with Step 1
		fi

		if $step1_completed; then
			step1_label="Step 1: Prerequisites Installed (Completed)"
		else
			step1_label="Step 1: Install prerequisites"
		fi

		CHOICE=$("${DIALOG_COMMON[@]}" --help-button --default-item "$default_item" \
			--menu "Guided Compilation:" 12 70 4 \
			"1" "$step1_label" \
			"2" "Step 2: Select device" \
			"3" "Step 3: Make firmware" \
			"5" "Step 4: (Optional) OTA Firmware" \
			3>&1 1>&2 2>&3)
		exit_status
	done
}

function show_help() {
	local item=$1
	case "$item" in
		"HELP 2")
			show_help_msgbox "Choose a device profile that closely matches your hardware specifications.\n\nYou can select from a \
'Cameras' profile with preconfigured environmental settings tailored for specific camera models, or opt for a 'Board' profile which \
provides basic configurations necessary to initialize the hardware.\n\nExperimental profiles are also available for bleeding edge testing." 14;;
		"HELP 1")
			show_help_msgbox "The 'Bootstrap' option initiates the installation of all necessary prerequisite software required for \
the compilation of the firmware.\n\nThis includes tools and libraries that are essential for building the firmware from source. Selecting \
this will ensure your environment is correctly set up to proceed with building Thingino without encountering missing dependencies. \
\n\nRequires super-user privileges." 14;;
		"HELP 3")
			show_help_msgbox "This option starts the firmware compilation process. The duration of this process depends on your \
computer's speed. Please be patient as it might take some time." 7;;
		"HELP 5")
			show_help_msgbox "After successfully compiling the firmware, this option allows you to send a compiled firmware image \
directly to your existing device via networking.  You'll need the IP address of the device you wish to upgrade." 8;;
		"HELP 7")
			show_help_msgbox "This function initiates an Over-the-Air (OTA) upgrade using the full firmware image. You'll need to \
specify the target device's IP address. It's used for comprehensive updates that include the bootloader, kernel, and filesystem." 8;;
		"HELP 8")
			show_help_msgbox "This option performs an OTA update with just the firmware update image, excluding the bootloader. \
You'll need to provide the target device's IP address. It's ideal for routine software updates after the initial full installation." 8;;
		*)
			show_help_msgbox "No help information is available for the selected item. Please choose another option or consult \
the thingino wiki for more details.";;
	esac
}

function execute_choice() {
	case $1 in
		1)	step1
			;;
		2)	step2
			;;
		3)	step3
			;;
		5)	step5
			;;
		7)  ota "upgrade"
			;;
		8)  ota "update"
			;;
		"HELP 7") show_help "HELP 7"
			;;
		"HELP 8") show_help "HELP 8"
			;;
		*)	echo "Program terminated or invalid option."
			;;
	esac
}

step1() {
	if [ -f ".prereqs.done" ]; then
		"${DIALOG_COMMON[@]}" --msgbox "Pre-requisites are already installed." 5 60
		return
	fi
	"${DIALOG_COMMON[@]}" --no-cancel --no-label "Back" --yes-label "Install" --yesno "Do you want to install pre-requisites?\n\nYou may skip this step if you are certain they are already installed." 8 60
	response=$?
	exec 3>&-
	if [ $response -eq 1 ]; then
		return
	elif [ $response -eq 255 ]; then
		closed_dialog
		return
	fi
	./scripts/dep_check.sh && touch .prereqs.done
}

step2() {
	if [ -n "$camera_value" ]; then
		exec 3>&1
		"${DIALOG_COMMON[@]}" --title "Confirmation" --yesno "You've already selected a device. Do you want to select again?" 6 60
		response=$?
		exec 3>&-
		if [ $response -eq 1 ]; then
			return  # User chooses not to reselect, keep the camera value as is
		elif [ $response -eq 255 ]; then
			closed_dialog
			return
		fi
		camera_value=""  # Reset if reselecting
	fi

	output=$(BR2_EXTERNAL=$PWD make -f board.mk)
	camera_value=$(echo "$output" | grep 'CAMERA =' | tail -n1 | awk -F' = ' '{print $2}')

	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --msgbox "Selected Device: \Z1$camera_value\Zn\n\nLets proceed to the next step to continue the build process." 8 60
		step2_completed=true
	else
		no_device
	fi
}


step3() {
	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --no-cancel --no-label "Back" --yesno "Making firmware for \Z1$camera_value\Zn...\n\nProceed with make?" 7 60
		response=$?
		exec 3>&-
		if [ $response -eq 1 ]; then
			return
		elif [ $response -eq 255 ]; then
			closed_dialog
			return
		fi
		BOARD=$camera_value make
		step3_completed=true
		"${DIALOG_COMMON[@]}" --msgbox "The firmware compilation process is now complete!\n\n" 5 70
	else
		no_device
	fi
}

step5() {
	if [ -n "$camera_value" ]; then
		CHOICE=$("${DIALOG_COMMON[@]}" --help-button --cancel-label "Back" --menu "OTA Operations" 9 50 2 \
			"7" "OTA Upgrade" \
			"8" "OTA Update" \
			3>&1 1>&2 2>&3)
		execute_choice "$CHOICE"
	else
		no_device
	fi
}

ota() {
	local action="$1"
	local warning=""
	local size=""

	if [ "$action" == "upgrade" ]; then
		warning="You are about to start a FULL UPGRADE, which includes upgrading the device's bootloader. This operation is critical and may disrupt the device's functionality if it fails. Proceed with caution.\n\nAre you sure you want to continue with the flashing process?"
		size=9
	else
		warning="Flashing will begin. Be careful, as this might disrupt the device's operation if it fails.\n\nAre you sure you want to continue?"
		size=8
	fi

	local temp_ip="$(mktemp)"
	"${DIALOG_COMMON[@]}" --title "Input IP" --inputbox "Enter the IP address for OTA $action" 8 78 2>"$temp_ip"
	local exit_status=$?

	if [ $exit_status -ne 0 ]; then
		echo "User canceled the operation."
		rm -f "$temp_ip"
		return
	fi

	local IP=$(<"$temp_ip")
	rm -f "$temp_ip"

	if [ -z "$IP" ]; then
		DIALOGRC=$temp_rc "${DIALOG_COMMON[@]}" --title "Warning" --msgbox "No IP address entered, returning to main menu." 5 78
		return
	fi

	if DIALOGRC=$temp_rc "${DIALOG_COMMON[@]}" --title "Warning" --yesno "$warning" $size 78; then
		echo "Proceeding with OTA $action to $IP..."
		BOARD=$camera_value make pack
		BOARD=$camera_value make "${action}_ota" IP="$IP"

		"${DIALOG_COMMON[@]}" --msgbox "OTA $action complete, please check your device!\n\nReturning to main menu." 7 70
		exit
	else
		echo "OTA $action canceled by user."
	fi
}

main_menu
