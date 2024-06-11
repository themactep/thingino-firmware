UI=dialog
GIT_BRANCH=$(git branch | grep ^* | awk '{print $2}')
GIT_HASH=$(git show -s --format=%H)
GIT_TIME=$(git show -s --format=%ci)
BACKTITLE="Thingino Firmware - ${GIT_BRANCH}+${GIT_HASH:0:7}, ${GIT_TIME}"
DIALOG_COMMON=($UI --keep-tite --colors --backtitle "$BACKTITLE" --cancel-label "Exit" --title "Thingino Buildroot")

temp_rc=$(mktemp)
temp_ip=$(mktemp)
cat <<-'EOF' > $temp_rc
dialog_color = (RED,WHITE,OFF)
screen_color = (WHITE,RED,ON)
EOF

function show_help_msgbox() {
	local message=$1
	local height=${2:-10}  # Default height is 10 if not provided
	local width=${3:-70}   # Default width is 70 if not provided

	"${DIALOG_COMMON[@]}" --title "Thingino help" --msgbox "$message" $height $width
}

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
	fi
}

exit_status() {
	EXITSTATUS=$?
	if [ $EXITSTATUS -eq 0 ]; then
		# Execute the option
		execute_choice "$CHOICE"
	elif [ $EXITSTATUS -eq 2 ]; then
		# Help button pressed
		show_help "$CHOICE"
	else
		exit
	fi
}

no_device() {
	"${DIALOG_COMMON[@]}" --msgbox "Error: No device selected.\n\nPlease select a device first." 7 60
}

closed_dialog() {
	echo "Dialog was closed or escaped." >&2
}
