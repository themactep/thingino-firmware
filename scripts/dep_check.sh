#!/bin/sh

preinit_check() {
echo "Running dependencies check..."

# Check if the current directory path contains spaces.
case "$PWD" in
*" "*)
	echo "Error: Current directory path \"$PWD\" cannot contain spaces"
	exit 1
	;;
esac

# Check for supported architecture.
host_arch=$(uname -m)
if [ "$host_arch" != "x86_64" ] && [ "$host_arch" != "aarch64" ]; then
	echo "Unsupported architecture: $host_arch. Only x86_64 and aarch64 are supported."
else
	echo "Host architecture is $host_arch"
fi

# Check dd (coreutils)
req=9.0
dd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+' | {
	read cur_ver || { echo "Unable to determine dd version" >&2; exit 1; }
	if [ "$(printf '%s\n' "$req" "$cur_ver" | sort -V | head -n1)" != "$req" ]; then
		echo "dd version $cur_ver is less than required $req.  Please update the coreutils for your distribution."
		exit 1
	else
		echo "dd version is $cur_ver, which is >= $req"
	fi
}

if [ $? -ne 0 ]; then
	exit 1
fi

echo "All preinit checks passed"

}

check_glibc_version() {
	min_version="2.31"
	# Check if running on Alpine with musl
	if ldd --version 2>&1 | grep -q musl; then
		echo "Alpine Linux detected with musl libc."
		return 0
	fi

	current_version=$(ldd --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
	if [ "$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)" = "$min_version" ]; then
		echo "glibc version is $current_version, which is >= $min_version"
	else
		echo "glibc version is $current_version, which is less than $min_version"
		echo "GLIBC Upgrade required, which usually means you need to upgrade the Operating System"
		exit 1
	fi
}

install_packages() {
	echo "The following packages are missing and need to be installed: $*"
	if $install_cmd $pkg_install_cmd "$@"; then
		echo "Installed $*"
	else
		echo "Failed to install $*"
	fi
}

# Check if sudo is available
if command -v sudo >/dev/null 2>&1; then
	install_cmd="sudo"
else
	install_cmd=""
fi

if [ -f ".prereqs.done" ]; then
	echo "dep_check.sh: dependencies OK, continue..."
	exit 0
fi

#pre init check
preinit_check

# Check glibc version
check_glibc_version

if [ -f /etc/os-release ]; then
	. /etc/os-release
	OS="$NAME"

	# Check ID_LIKE for Debian-based identification first
	case "$ID_LIKE" in
		*debian*)
			echo "Detected as Debian-based via ID_LIKE"
			pkg_manager="dpkg"
			pkg_check_command="dpkg-query -W -f='\${Status}'"
			pkg_install_cmd="apt-get install -y"
			pkg_update_cmd="apt-get update"
			packages="build-essential bc bison cpio cmake curl file flex gawk git libncurses-dev make nano rsync unzip u-boot-tools vim-tiny wget whiptail dialog"
			;;
		*)
			case "$ID" in
				ubuntu|debian|linuxmint|zorin)
					echo "Detected as Debian-based via ID"
					pkg_manager="dpkg"
					pkg_check_command="dpkg-query -W -f='\${Status}'"
					pkg_install_cmd="apt-get install -y"
					pkg_update_cmd="apt-get update"
					packages="build-essential bc bison cpio cmake curl file flex gawk git libncurses-dev make nano rsync unzip u-boot-tools vim-tiny wget whiptail dialog"
					;;
				rhel|centos|fedora)
					echo "RedHat-based"
					pkg_manager="rpm"
					pkg_check_command="rpm -q --whatprovides"
					pkg_install_cmd="dnf install -y"
					packages="gcc make bc bison cpio cmake curl file flex gawk git nano ncurses-devel rsync unzip uboot-tools wget newt dialog"
					;;
				arch)
					echo "Arch-based"
					pkg_manager="pacman"
					pkg_check_command="pacman -Q"
					pkg_install_cmd="pacman -S --noconfirm"
					packages="base-devel bc bison cpio cmake curl file flex gawk git nano ncurses make rsync unzip uboot-tools wget libnewt dialog"
					;;
				alpine)
					echo "Alpine Linux"
					pkg_manager="apk"
					pkg_check_command="apk info -e"
					pkg_install_cmd="apk add"
					packages="bash build-base bc bison cpio cmake curl file flex gawk git nano ncurses-dev make rsync unzip uboot-tools wget newt dialog perl findutils grep"
					;;
				opensuse*)
					echo "OpenSUSE Tumbleweed"
					pkg_manager="zypper"
					pkg_check_command="zypper search -i"
					pkg_install_cmd="zypper install -y"
					packages="gcc make bc bison cpio cmake curl file flex gawk git ncurses-devel rsync unzip u-boot-tools wget newt dialog perl findutils grep"
					;;
				*)
					echo "Unsupported OS: $ID"
					exit 1
					;;
			esac
			;;
	esac
else
	echo "Could not determine the operating system."
	exit 1
fi

# Check installed packages based on the package manager
packages_to_install=""

for pkg in $packages; do
	case "$pkg_manager" in
		dpkg)
			# Special case for vim-tiny: check if either vim-tiny or full vim is installed
			if [ "$pkg" = "vim-tiny" ]; then
				if ! $pkg_check_command "vim-tiny" 2>/dev/null | grep -q "install ok installed" && \
				   ! $pkg_check_command "vim" 2>/dev/null | grep -q "install ok installed"; then
					packages_to_install="$packages_to_install $pkg"
				else
					echo "Package vim-tiny or vim is installed"
				fi
			elif ! $pkg_check_command "$pkg" 2>/dev/null | grep -q "install ok installed"; then
				packages_to_install="$packages_to_install $pkg"
			else
				echo "Package $pkg is installed"
			fi
			;;
		rpm)
			if ! $pkg_check_command "$pkg" >/dev/null 2>&1; then
				packages_to_install="$packages_to_install $pkg"
			else
				echo "Package $pkg is installed"
			fi
			;;
		pacman)
			if ! $pkg_check_command "$pkg" >/dev/null 2>&1; then
				packages_to_install="$packages_to_install $pkg"
			else
				echo "Package $pkg is installed"
			fi
			;;
		apk)
			if ! $pkg_check_command "$pkg" >/dev/null 2>&1; then
				packages_to_install="$packages_to_install $pkg"
			else
				echo "Package $pkg is installed"
			fi
			;;
		zypper)
			if ! $pkg_check_command "$pkg" >/dev/null 2>&1; then
				packages_to_install="$packages_to_install $pkg"
			else
				echo "Package $pkg is installed"
			fi
			;;
		*)
			echo "Package manager $pkg_manager is not supported."
			exit 1
			;;
	esac
done

# Install missing packages if any
if [ -n "$packages_to_install" ]; then
	echo "The following packages are missing and need to be installed:"
	for pkg in $packages_to_install; do
		echo "- $pkg"
	done

	echo "Do you wish to proceed with the installation? (yes/no): "
	read user_input
	if [ "$user_input" = "yes" ] || [ "$user_input" = "y" ]; then
		if [ "$(id -u)" -ne 0 ] && [ -z "$install_cmd" ]; then
			echo "This script needs superuser privileges to install packages."
			echo "Please run it with sudo or as root."
			exit 1
		fi
		if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
			echo "Updating package list..."
			$install_cmd $pkg_update_cmd
		fi
		install_packages $packages_to_install
	else
		echo "Installation aborted by the user."
		exit 1
	fi
else
	echo "All required packages are installed"
	if [ ! -f ".prereqs.done" ]; then
		touch .prereqs.done
	fi
fi
