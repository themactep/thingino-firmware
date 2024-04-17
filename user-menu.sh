#!/bin/bash

export NCURSES_NO_UTF8_ACS=1

source ./scripts/menu/menu-common.sh

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
		clear
	fi
}

function main_menu() {
	check_and_install_dialog
	while true; do
		CHOICE=$("${DIALOG_COMMON[@]}" --help-button --menu \
		"\Zb\Z1THINGINO\Zn is an open-source replacement firmware designed specifically for   \Zr\Z4Ingenic\Zn SoC based devices, offering freedom from restrictive stock firmware and providing a user-friendly alternative to other complex options.  \
		\n\nJoin us in unlocking the full potential of your hardware with \Zb\Z1THINGINO\Zn's robust and customizable features! \
		\n\nSelect an option:" 18 80 20 \
			"1" "Introduction" \
			"2" "Guided Compilation" \
			"3" "Main Menu" \
			"4" "Exit" \
			3>&1 1>&2 2>&3)

			exit_status
	done
}

function show_help() {
	local item=$1
	case "$item" in
		"HELP 1")
			show_help_msgbox "Displays a comprehensive introduction to THINGINO, outlining its core features and benefits, and how it transforms your IP camera experience." 7;;
		"HELP 2")
			show_help_msgbox "Initiates the guided compilation process, which assists you step-by-step in setting up THINGINO on your device. Ideal for users who are configuring THINGINO for the first time." 7;;
		"HELP 3")
			show_help_msgbox "Launches you to the main menu, where you can access all key features and settings of THINGINO. Navigate through options to customize and control your firmware installation." 7;;
		"HELP 4")
			show_help_msgbox "Exits the THINGINO program safely." 5;;
		*)
			show_help_msgbox "No help information is available for the selected item. Please choose another option or consult the thingino wiki for more details.";;
	esac
}

function execute_choice(){
	case $1 in
		1)
			"${DIALOG_COMMON[@]}" --msgbox "Thingino is an open source firmware for devices built on an Ingenic SoC. Originally derived from OpenIPC it has branched to an independent project with a different vision and a different approach.\n\n
Thingino does not try to build a universal firmware that would be used on multiple models. Instead, we build a firmware which is nicely tailored to the targeted hardware, with minimum overhead.\n\n
Thingino is young but develops fast. You should expect frequent updates, exciting new features, and occasional breaking changes.
Thingino uses a custom version of prudynt as a go-to streamer while working on its own fully open modular solution - Raptor." 15 100
			;;
		2)
			./scripts/menu/menu2-guided.sh
			;;
		3)
			./scripts/menu/main-menu.sh
			exit
			;;
		4)
			exit
			;;
		*)
			exit
			;;
	esac
}

main_menu
