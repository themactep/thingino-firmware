#!/bin/bash

camera_value=""
step1_completed=false
step2_completed=false

source ./scripts/menu/menu-common.sh

main_menu() {
	local default_item="1"

	while true; do
		if $step1_completed && ! $step2_completed; then
			default_item="2"
		elif $step2_completed; then
			default_item="3"
		fi

		CHOICE=$("${DIALOG_COMMON[@]}" --help-button --default-item "$default_item" \
			--menu "Please select:" 15 50 4 \
			"1" "Step 1: Select device" \
			"2" "Step 2: Make firmware" \
			"3" "Step 3: Make Image" \
			3>&1 1>&2 2>&3)

			exit_status
	done
}

function show_help() {
	local item=$1
	case "$item" in
		"HELP 1")
			show_help_msgbox "Choose a device profile that closely matches your hardware specifications.\n\nYou can select from a 'Cameras' profile with preconfigured environmental settings tailored for specific camera models, or opt for a 'Board' profile which provides basic configurations necessary to initialize the hardware.\n\nExperimental profiles are also available for bleeding edge testing." 15;;
		"HELP 2")
			show_help_msgbox "This option starts the firmware compilation process. The duration of this process depends on your computer's speed. Please be patient as it might take some time." 8;;
		"HELP 3")
			show_help_msgbox "After successfully compiling the firmware, this option allows you to create an image file that can be flashed to your device. Use this to update your device with the new firmware." 8;;
		*)
			show_help_msgbox "No help information is available for the selected item. Please choose another option or consult the thingino wiki for more details.";;
	esac
}

function execute_choice() {
	case $1 in
		1)
			step1
			;;
		2)
			step2
			;;
		3)
			step3
			;;
		*)
			clear
			echo "Program terminated or invalid option."
			;;
	esac
}

step1() {
	if [ -n "$camera_value" ]; then
		exec 3>&1
		"${DIALOG_COMMON[@]}" --title "Confirmation" --yesno "You've already selected a device. Do you want to select again?" 7 60
		response=$?
		exec 3>&-
		if [ $response -eq 1 ]; then
			return  # User chooses not to reselect, keep the camera value as is
		elif [ $response -eq 255 ]; then
			echo "Dialog was closed or escaped." >&2
			return
		fi
		camera_value=""  # Reset if reselecting
	fi

	output=$(BR2_EXTERNAL=$PWD make -f board.mk)
	camera_value=$(echo "$output" | grep 'CAMERA =' | tail -n1 | awk -F' = ' '{print $2}')

	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --msgbox "Selected Device: $camera_value\n\nNext, proceed to step 2, to begin the make process." 10 40
		step1_completed=true
	else
		"${DIALOG_COMMON[@]}" --msgbox "Error: No device selected.\n\nPlease select a device first." 7 40
	fi
}

step2() {
	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --no-cancel --no-label "Back" --yesno "Making firmware for $camera_value...\n\nProceed with make?" 8 40
		response=$?
		exec 3>&-
		if [ $response -eq 1 ]; then
			return
		elif [ $response -eq 255 ]; then
			echo "Dialog was closed or escaped." >&2
			return
		fi
		BOARD=$camera_value make
		step2_completed=true
		"${DIALOG_COMMON[@]}" --msgbox "Make process complete!\\nYou may proceed to create an image." 7 40
	else
		"${DIALOG_COMMON[@]}" --msgbox "Error: No device selected.\n\nPlease select a device first." 7 40
	fi
}

step3() {
	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --msgbox "Making image for $camera_value...\n\nPress OK to begin." 8 40
		BOARD=$camera_value make pack
		step2_completed=true
		"${DIALOG_COMMON[@]}" --msgbox "Image process complete!\\n\nYour images are located in \n$HOME/output/$camera_value/images" 10 40
	else
		"${DIALOG_COMMON[@]}" --msgbox "Error: No device selected.\n\nPlease select a device first." 7 40
	fi
}

main_menu
