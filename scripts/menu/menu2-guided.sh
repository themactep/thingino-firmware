#!/bin/bash

camera_value=""
step1_completed=false
step2_completed=false
step3_completed=false

source ./scripts/menu/menu-common.sh

main_menu() {
	local default_item="1"

	while true; do
		if $step1_completed && ! $step2_completed; then
			default_item="2"
		elif $step2_completed && ! $step3_completed; then
			default_item="3"
		elif $step3_completed; then
			default_item="4"
		fi

		CHOICE=$("${DIALOG_COMMON[@]}" --help-button --default-item "$default_item" \
			--menu "Guided Compilation:" 11 70 4 \
			"1" "Step 1: Select device" \
			"2" "Step 2: Install prerequsites" \
			"3" "Step 3: Make firmware" \
			"4" "Step 4: Make Image" \
			3>&1 1>&2 2>&3)

			exit_status
	done
}

function show_help() {
	local item=$1
	case "$item" in
		"HELP 1")
			show_help_msgbox "Choose a device profile that closely matches your hardware specifications.\n\nYou can select from a \
'Cameras' profile with preconfigured environmental settings tailored for specific camera models, or opt for a 'Board' profile which \
provides basic configurations necessary to initialize the hardware.\n\nExperimental profiles are also available for bleeding edge testing." 14;;
		"HELP 2")
			show_help_msgbox "The 'Bootstrap' option initiates the installation of all necessary prerequisite software required for \
the compilation of the firmware.\n\nThis includes tools and libraries that are essential for building the firmware from source. Selecting \
this will ensure your environment is correctly set up to proceed with building THINGINO without encountering missing dependencies. \
\n\nRequires super-user privileges." 14;;
		"HELP 3")
			show_help_msgbox "This option starts the firmware compilation process. The duration of this process depends on your \
computer's speed. Please be patient as it might take some time." 7;;
		"HELP 4")
			show_help_msgbox "After successfully compiling the firmware, this option allows you to create an image file that can \
be flashed to your device. Use this to update your device with the new firmware." 7;;
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
		4)	step4
			;;
		*)	clear
			echo "Program terminated or invalid option."
			;;
	esac
}

step1() {
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
		"${DIALOG_COMMON[@]}" --msgbox "Selected Device: \Z1$camera_value\Zn\n\nNext, proceed to step 2, to continue the build process." 7 60
		step1_completed=true
	else
		no_device
	fi
}

step2() {
	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --no-cancel --no-label "Back" --yes-label "Install" --yesno "Do you want to install pre-requisites?\n\nYou may skip this step if you are certain they are already installed." 8 60
		response=$?
		exec 3>&-
		if [ $response -eq 1 ]; then
			step2_completed=true
			return
		elif [ $response -eq 255 ]; then
			closed_dialog
			return
		fi
		sudo BOARD=$camera_value make bootstrap
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
		"${DIALOG_COMMON[@]}" --msgbox "The firmware compilation process is now complete!\n\nYou can now proceed to create a firmware image, which is necessary for flashing the firmware onto your device." 8 70
	else
		no_device
	fi
}

step4() {
	if [ -n "$camera_value" ]; then
		"${DIALOG_COMMON[@]}" --no-cancel --no-label "Back" --yes-label "OK" --yesno "Making image for \Z1$camera_value\Zn...\n\nPress OK to begin." 7 60
		response=$?
		exec 3>&-
		if [ $response -eq 1 ]; then
			return
		elif [ $response -eq 255 ]; then
			closed_dialog
			return
		fi
		BOARD=$camera_value make pack
		step3_completed=true
		"${DIALOG_COMMON[@]}" --msgbox "Image process complete!\\n\nYour images are located in \n\Z1$HOME/output/$camera_value/images\Zn" 8 60
		exit
	else
		no_device
	fi
}

main_menu
