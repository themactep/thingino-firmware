#!/bin/bash

check_glibc_version() {
	local min_version="2.38"
	local current_version=$(ldd --version | head -n1 | grep -oP '\d+\.\d+' | head -1)
	if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" = "$min_version" ]; then
		echo "glibc version is $current_version, which is >= $min_version."
	else
		echo -e "glibc version is $current_version, which is less than $min_version.\n GLIBC Upgrade required, which usually means you need to upgrade the Operating System."
		exit 1
	fi
}

install_packages() {
	local package=$1
	echo "Package $package is NOT installed. Attempting to install..."
	if $install_cmd $pkg_install_cmd $package; then
		echo "Installed $package"
	else
		echo "Failed to install $package"
	fi
}

if command -v sudo &> /dev/null; then
	install_cmd="sudo"
else
	install_cmd=""
fi

if [ -f /etc/os-release ]; then
	. /etc/os-release
	OS=$NAME
	case $ID in
		ubuntu|debian)
			echo "Debian-based"
			pkg_manager="dpkg"
			pkg_check_command="-l"
			pkg_install_cmd="apt-get install -y"
			pkg_list=$(dpkg -l)
			declare -A packages=(
				[build-essential]=build-essential
				[bc]=bc
				[bison]=bison
				[cpio]=cpio
				[curl]=curl
				[file]=file
				[flex]=flex
				[gawk]=gawk
				[git]=git
				[libncurses-dev]=libncurses-dev
				[make]=make
				[rsync]=rsync
				[unzip]=unzip
				[wget]=wget
				[whiptail]=whiptail
				[dialog]=dialog
			)
			;;
		rhel|centos|fedora)
			echo "RedHat-based"
			pkg_manager="rpm"
			pkg_check_command="-qa"
			pkg_install_cmd="dnf install -y"
			pkg_list=$(rpm -qa)
			declare -A packages=(
				[gcc]=gcc
				[make]=make
				[bc]=bc
				[bison]=bison
				[cpio]=cpio
				[curl]=curl
				[file]=file
				[flex]=flex
				[gawk]=gawk
				[git]=git
				[ncurses-devel]=ncurses-devel
				[rsync]=rsync
				[unzip]=unzip
				[wget]=wget
				[newt]=newt
				[dialog]=dialog
			)
			;;
		arch)
			echo "Arch-based"
			pkg_manager="pacman"
			pkg_check_command="-Q"
			pkg_install_cmd="pacman -S --noconfirm"
			pkg_list=$(pacman -Q)
			declare -A packages=(
				[base-devel]=base-devel
				[bc]=bc
				[bison]=bison
				[cpio]=cpio
				[curl]=curl
				[file]=file
				[flex]=flex
				[gawk]=gawk
				[git]=git
				[ncurses]=ncurses
				[make]=make
				[rsync]=rsync
				[unzip]=unzip
				[wget]=wget
				[libnewt]=libnewt
				[dialog]=dialog
			)
			;;
		alpine)
			echo "Alpine Linux"
			pkg_manager="apk"
			pkg_check_command="info -e"
			pkg_install_cmd="apk add"
			pkg_list=$(apk info)
			declare -A packages=(
				[build-base]=build-base
				[bc]=bc
				[bison]=bison
				[cpio]=cpio
				[curl]=curl
				[file]=file
				[flex]=flex
				[gawk]=gawk
				[git]=git
				[ncurses-dev]=ncurses-dev
				[make]=make
				[rsync]=rsync
				[unzip]=unzip
				[wget]=wget
				[libnewt]=newt
				[dialog]=dialog
			)
			;;
		*)
			echo "Unsupported OS"
			exit 1
			;;
	esac
else
	echo "Could not determine the operating system."
	exit 1
fi

check_glibc_version

packages_to_install=()

for key in "${!packages[@]}"; do
	if ! echo "$pkg_list" | grep -qw "${packages[$key]}"; then
		packages_to_install+=("${packages[$key]}")
	else
		echo "Package ${packages[$key]} is installed."
	fi
done

if [ ${#packages_to_install[@]} -ne 0 ]; then
	echo "The following packages are missing and need to be installed:"
	for pkg in "${packages_to_install[@]}"; do
		echo "- $pkg"
	done

	read -p "Do you wish to proceed with the installation? (yes/no): " user_input
	if [ "$user_input" = "yes" ] || [ "$user_input" = "y" ]; then
		if [ "$EUID" -ne 0 ] && [ -z "$install_cmd" ]; then
			echo "This script needs superuser privileges to install packages."
			echo "Please run it with sudo or as root."
			exit 1
		fi
		for pkg in "${packages_to_install[@]}"; do
			install_packages $pkg
		done
	else
		echo "Installation aborted by the user."
		exit 0
	fi
else
	echo "All packages are installed."
fi
