#!/bin/sh

dep_check() {
	# Check if both dialog and Bash are installed
	if ! command -v dialog >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1; then
		echo "'dialog' and/or 'bash' are not installed, which are required for this script to run."
		echo "Do you want to install prerequisites now? [Y/n] "
		read yn
		case "$yn" in
			[Yy]* | "" )
				echo "Attempting to install prerequisites..."
				./scripts/dep_check.sh
				;;
			[Nn]* )
				echo "Cannot proceed without 'dialog' and 'bash'. Exiting..."
				exit 1
				;;
			* )
				echo "Please answer yes or no."
				dep_check
				;;
		esac
	fi
}

dep_check

if [ -z "$BASH_VERSION" ]; then
    exec bash "$0" "$@"
fi

export NCURSES_NO_UTF8_ACS=1

source ./scripts/menu/menu-common.sh

function main_menu() {
	while true; do
		CHOICE=$("${DIALOG_COMMON[@]}" --help-button --menu \
		"\Zb\Z1Thingino\Zn is an open-source replacement firmware designed specifically for   \Zr\Z4Ingenic\Zn SoC based devices, offering freedom from restrictive stock firmware and providing a user-friendly alternative to other complex options.  \
		\n\nJoin us in unlocking the full potential of your hardware with \Zb\Z1Thingino\Zn's robust and customizable features! \
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
			show_help_msgbox "Displays a comprehensive introduction to Thingino, outlining its core features and benefits, and how it transforms your IP camera experience." 7;;
		"HELP 2")
			show_help_msgbox "Initiates the guided compilation process, which assists you step-by-step in setting up Thingino on your device. Ideal for users who are configuring Thingino for the first time." 7;;
		"HELP 3")
			show_help_msgbox "Launches you to the main menu, where you can access all key features and settings of Thingino. Navigate through options to customize and control your firmware installation." 7;;
		"HELP 4")
			show_help_msgbox "Exits the Thingino program safely." 5;;
		*)
			show_help_msgbox "No help information is available for the selected item. Please choose another option or consult the Thingino Wiki for more details.";;
	esac
}

function execute_choice(){
	case $1 in
		1)
			"${DIALOG_COMMON[@]}" --msgbox "Thingino is an independent open source firmware project for devices built on an Ingenic SoC.\n\n
Thingino does not try to build a universal firmware that would be used on multiple models. Instead, we build a firmware which is nicely tailored to the targeted hardware, with minimum overhead.\n\n
Thingino is young but develops fast. You should expect frequent updates, exciting new features, and occasional breaking changes.
Thingino uses a custom version of prudynt as a go-to streamer while working on its own fully open modular solution - Raptor.\n\n
This menu provides a basic interface to select and build a firmware profile, but you don't have to use it -- you can build everything fully from the command line if you prefer. See the wiki for more information!" 17 100
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
