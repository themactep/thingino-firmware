#!/bin/bash

temp_rc=$(mktemp)
cat <<-'EOF' > $temp_rc
dialog_color = (RED,WHITE,OFF)
screen_color = (WHITE,RED,ON)
EOF

UI=dialog
GIT_BRANCH=$(git branch | grep ^* | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(git show -s --format=%ci)
BACKTITLE="THINGINO Firmware - ${GIT_BRANCH}+${GIT_HASH:0:7}, ${GIT_TIME}"

check_and_install_dialog() {
	if ! command -v dialog &> /dev/null; then
		echo "'dialog' is not installed. It is required for this script to run."
		read -p "Do you want to install 'dialog' now? [Y/n] " yn
		case $yn in
			[Yy]* )
				echo "Attempting to install 'dialog'..."
				sudo apt-get update; sudo apt-get install -y --no-install-recommends --no-install-suggests dialog
				check_and_install_dialog
				;;
			[Nn]* )
				echo "Cannot proceed without 'dialog'. Exiting..."
				exit 1
				;;
			* )
				echo "Please answer yes or no."
				check_and_install_dialog
				;;
		esac
	else
		echo "'dialog' is installed."
	fi
}

function main_menu() {
	check_and_install_dialog
	while true; do
		CHOICE=$($UI --colors --backtitle "$BACKTITLE" --erase-on-exit --cancel-label "Exit" --help-button --title "THINGINO Buildroot" --menu "Choose an option" 18 110 30 \
			"menuconfig" "Proceed to the buildroot menu (toolchain, kernel, and rootfs)" \
			"pack_full" "Create a full firmware image"  \
			"pack_update" "Create an update firmware image (no bootloader)" \
			"pad_full" "Pad the full firmware image to 16MB" \
			"pad_update" "Pad the update firmware image to 16MB" \
			"clean" "Clean before reassembly"  \
			"distclean" "Start building from scratch"  \
			"make" "Generate firmware" \
			"upgrade_ota" "Upload the full firmware file to the camera over network, and flash it"  \
			"update_ota" "Upload the update firmware file to the camera over network, and flash it"  \
			3>&1 1>&2 2>&3)

		EXITSTATUS=$?
		if [ $EXITSTATUS -eq 0 ]; then
			# Execute the option
			execute_choice "$CHOICE"
		elif [ $EXITSTATUS -eq 2 ]; then
			# Help button pressed
			show_help "$CHOICE"
		else
			# Cancel/ESC, exit the loop
			break
		fi
	done
}

function show_help_msgbox() {
	$UI --colors --backtitle "$BACKTITLE" --title "THINGINO help" --msgbox "$1" 10 70
}

function show_help() {
	local item=$1
	case "$item" in
		"HELP menuconfig")
			show_help_msgbox "Launches a graphical interface for configuring the toolchain, kernel options, and the packages that will be included in your root filesystem. It's a crucial step for customizing your build according to your needs.";;
		"HELP pack_full")
			show_help_msgbox "This option initiates the process of building a complete firmware image. This includes the bootloader, the kernel, and the root filesystem. It's suitable for initial installations or complete upgrades of a device.";;
		"HELP pack_update")
			show_help_msgbox "Selecting this option builds a firmware update image excluding the bootloader component. This is typically used for Over-the-Air (OTA) updates, allowing for the device's software to be updated without altering the bootloader.";;
		"HELP pad_full")
			show_help_msgbox "This command increases the size of the full firmware image to 16MB by adding zeros to the end. This padding process ensures the firmware image meets the size requirement for certain flashing tools or devices.";;
		"HELP pad_update")
			show_help_msgbox "Similar to 'pad_full', this option pads the update firmware image to reach 16MB in size. This is particularly useful when the update image needs to match a specific size for the update process to succeed.";;
		"HELP clean")
			show_help_msgbox "The 'clean' command removes most of the files generated during the build process but preserves your configuration settings. This allows you to rebuild your firmware quickly without starting from scratch.";;
		"HELP distclean")
			show_help_msgbox "Choosing 'distclean' will clean your build environment more thoroughly than 'clean'. It removes all generated files, including your configuration and all cached build files. Use this to completely restart the build process.";;
		"HELP make")
			show_help_msgbox "This option starts the compilation process for the entire firmware project based on your current configuration settings. It's a key step in creating the custom thingino firmware for your device.";;
		"HELP upgrade_ota")
			show_help_msgbox "This function initiates an Over-the-Air (OTA) upgrade using the full firmware image. You'll need to specify the target device's IP address. It's used for comprehensive updates that include the bootloader, kernel, and filesystem.";;
		"HELP update_ota")
			show_help_msgbox "This option performs an OTA update with just the firmware update image, excluding the bootloader. You'll need to provide the target device's IP address. It's ideal for routine software updates after the initial full installation.";;
		*)
			show_help_msgbox "No help information is available for the selected item. Please choose another option or consult the thingino wiki for more details.";;
	esac
}

execute_choice() {
	case $1 in
		menuconfig | pack_full | pack_update | pad_full | pad_update | make)
			make $1
			exit
			;;
		clean | distclean)
			make $1
			;;
		upgrade_ota | update_ota)
			local action="upgrade"
			local warning="You are about to start a full upgrade, which includes upgrading the device's bootloader. This operation is critical and may disrupt the device's functionality if it fails. Proceed with caution. Are you sure you want to continue with the flashing process?"
			[ "$1" = "update_ota" ] && {
				action="update"
				warning="Flashing will begin. Be careful, as this might disrupt the device's operation if it fails. Are you sure you want to continue?"
			}

			IP=$($UI --backtitle "$BACKTITLE" --stdout --title "Input IP" --inputbox "Enter the IP address for OTA $action" 8 78)
			if [ $? -eq 0 ]; then
				if $(DIALOGRC=$temp_rc $UI --backtitle "$BACKTITLE" --stdout --colors --title "Warning" --yesno "$warning" 12 78); then
					echo "Proceeding with OTA $action to $IP..."
					make $1 IP=$IP
					exit
				else
					echo "OTA $action canceled by user."
				fi
			else
				echo "User canceled the operation."
			fi
			rm -f $temp_rc
			;;
		*)
			echo "Invalid choice."
			;;
	esac
}

# Start the main menu
main_menu
