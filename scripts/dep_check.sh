#!/bin/bash

check_glibc_version() {
	local min_version="2.31"
	# Check if running on Alpine with musl
	if ldd --version 2>&1 | grep -q musl; then
		echo "Alpine Linux detected with musl libc."
		return 0
	fi

	local current_version=$(ldd --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
	if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" = "$min_version" ]; then
		echo "glibc version is $current_version, which is >= $min_version."
	else
		echo -e "glibc version is $current_version, which is less than $min_version.\nGLIBC Upgrade required, which usually means you need to upgrade the Operating System."
		exit 1
	fi
}

install_packages() {
	local packages=("$@")
	echo "The following packages are missing and need to be installed: ${packages[*]}"
	if $install_cmd $pkg_install_cmd "${packages[@]}"; then
		echo "Installed ${packages[*]}"
	else
		echo "Failed to install ${packages[*]}"
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

	# Check ID_LIKE for Debian-based identification first
	if [[ "$ID_LIKE" =~ debian ]]; then
		echo "Detected as Debian-based via ID_LIKE"
		pkg_manager="dpkg"
		pkg_check_command="dpkg-query -W -f='${Status}'"
		pkg_install_cmd="apt-get install -y"
		pkg_update_cmd="apt-get update"
		declare -A packages=(
			[build-essential]='build-essential'
			[bc]='bc'
			[bison]='bison'
			[cpio]='cpio'
			[cmake]='cmake'
			[curl]='curl'
			[file]='file'
			[flex]='flex'
			[gawk]='gawk'
			[git]='git'
			[libncurses-dev]='libncurses-dev'
			[make]='make'
			[rsync]='rsync'
			[unzip]='unzip'
			[u-boot-tools]='u-boot-tools'
			[wget]='wget'
			[whiptail]='whiptail'
			[dialog]='dialog'
		)
	else
		# Check specific IDs if ID_LIKE didn't catch it
		case "$ID" in
			ubuntu|debian|linuxmint|zorin)
				echo "Detected as Debian-based via ID"
				pkg_manager="dpkg"
				pkg_check_command="dpkg-query -W -f='${Status}'"
				pkg_install_cmd="apt-get install -y"
				pkg_update_cmd="apt-get update"
				declare -A packages=(
					[build-essential]='build-essential'
					[bc]='bc'
					[bison]='bison'
					[cpio]='cpio'
					[cmake]='cmake'
					[curl]='curl'
					[file]='file'
					[flex]='flex'
					[gawk]='gawk'
					[git]='git'
					[libncurses-dev]='libncurses-dev'
					[make]='make'
					[rsync]='rsync'
					[unzip]='unzip'
					[u-boot-tools]='u-boot-tools'
					[wget]='wget'
					[whiptail]='whiptail'
					[dialog]='dialog'
				)
				;;
			rhel|centos|fedora)
				echo "RedHat-based"
				pkg_manager="rpm"
				pkg_check_command="rpm -q"
				pkg_install_cmd="dnf install -y"
				declare -A packages=(
					[gcc]='gcc'
					[make]='make'
					[bc]='bc'
					[bison]='bison'
					[cpio]='cpio'
					[cmake]='cmake'
					[curl]='curl'
					[file]='file'
					[flex]='flex'
					[gawk]='gawk'
					[git]='git'
					[ncurses-devel]='ncurses-devel'
					[rsync]='rsync'
					[unzip]='unzip'
					[wget]='wget'
					[newt]='newt'
					[dialog]='dialog'
				)
				;;
			arch)
				echo "Arch-based"
				pkg_manager="pacman"
				pkg_check_command="pacman -Q"
				pkg_install_cmd="pacman -S --noconfirm"
				declare -A packages=(
					[base-devel]='base-devel'
					[bc]='bc'
					[bison]='bison'
					[cpio]='cpio'
					[cmake]='cmake'
					[curl]='curl'
					[file]='file'
					[flex]='flex'
					[gawk]='gawk'
					[git]='git'
					[ncurses]='ncurses'
					[make]='make'
					[rsync]='rsync'
					[unzip]='unzip'
					[wget]='wget'
					[libnewt]='libnewt'
					[dialog]='dialog'
				)
				;;
			alpine)
				echo "Alpine Linux"
				pkg_manager="apk"
				pkg_check_command="apk info -e"
				pkg_install_cmd="apk add"
				declare -A packages=(
					[build-base]='build-base'
					[bc]='bc'
					[bison]='bison'
					[cpio]='cpio'
					[cmake]='cmake'
					[curl]='curl'
					[file]='file'
					[flex]='flex'
					[gawk]='gawk'
					[git]='git'
					[ncurses-dev]='ncurses-dev'
					[make]='make'
					[rsync]='rsync'
					[unzip]='unzip'
					[wget]='wget'
					[newt]='newt'
					[dialog]='dialog'
					[perl]='perl'
					[findutils]='findutils'
					[grep]='grep'
				)
				;;
			opensuse-tumbleweed)
				echo "OpenSUSE Tumbleweed"
				pkg_manager="zypper"
				pkg_check_command="zypper search -i"
				pkg_install_cmd="zypper install -y"
				declare -A packages=(
					[gcc]='gcc'
					[make]='make'
					[bc]='bc'
					[bison]='bison'
					[cpio]='cpio'
					[cmake]='cmake'
					[curl]='curl'
					[file]='file'
					[flex]='flex'
					[gawk]='gawk'
					[git]='git'
					[ncurses-devel]='ncurses-devel'
					[rsync]='rsync'
					[unzip]='unzip'
					[wget]='wget'
					[newt]='newt'
					[dialog]='dialog'
					[perl]='perl'
					[findutils]='findutils'
					[grep]='grep'
				)
				;;
			*)
				echo "Unsupported OS: $ID"
				exit 1
				;;
		esac
	fi
else
	echo "Could not determine the operating system."
	exit 1
fi

check_glibc_version

# Check installed packages based on the package manager
packages_to_install=()

for key in "${!packages[@]}"; do
	case "$pkg_manager" in
		dpkg)
			if ! dpkg-query -W -f='${Status}' "${packages[$key]}" 2>/dev/null | grep -q "install ok installed"; then
				packages_to_install+=("${packages[$key]}")
			else
				echo "Package ${packages[$key]} is installed."
			fi
			;;
		rpm)
			if ! rpm -q "${packages[$key]}" &>/dev/null; then
				packages_to_install+=("${packages[$key]}")
			else
				echo "Package ${packages[$key]} is installed."
			fi
			;;
		pacman)
			if ! pacman -Q "${packages[$key]}" &>/dev/null; then
				packages_to_install+=("${packages[$key]}")
			else
				echo "Package ${packages[$key]} is installed."
			fi
			;;
		apk)
			if ! apk info -e "${packages[$key]}" &>/dev/null; then
				packages_to_install+=("${packages[$key]}")
			else
				echo "Package ${packages[$key]} is installed."
			fi
			;;
		zypper)
			if ! zypper search -i "${packages[$key]}" &>/dev/null; then
				packages_to_install+=("${packages[$key]}")
			else
				echo "Package ${packages[$key]} is installed."
			fi
			;;
		*)
			echo "Package manager $pkg_manager is not supported."
			exit 1
			;;
	esac
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
		if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
			echo "Updating package list..."
			$install_cmd $pkg_update_cmd
		fi
		install_packages "${packages_to_install[@]}"
	else
		echo "Installation aborted by the user."
		exit 0
	fi
else
	echo "All packages are installed."
fi
