#!/bin/sh

if [ -f .prereqs.done ]; then
	exit 0
fi

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

	# Check dd (coreutils or uutils)
	dd_version_output=$(dd --version 2>&1 | head -n1)

	# Check if it's uutils coreutils (Rust rewrite)
	if echo "$dd_version_output" | grep -q "uutils coreutils"; then
		echo "dd (uutils coreutils) detected - OK"
	else
		# Classic coreutils - require >= 9.0
		req=9.0
		echo "$dd_version_output" | grep -oE '[0-9]+\.[0-9]+' | {
			read cur_ver || {
				echo "Unable to determine dd version" >&2
				exit 1
			}
			if [ "$(printf '%s\n' "$req" "$cur_ver" | sort -V | head -n1)" != "$req" ]; then
				echo "dd version $cur_ver is less than required $req."
				echo "Please update the coreutils for your distribution."
				exit 1
			else
				echo "dd version is $cur_ver, which is >= $req"
			fi
		}
	fi

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

check_required_tools() {
	required_tools="rg shfmt npx"
	missing_tools=""

	for tool in $required_tools; do
		if ! command -v "$tool" >/dev/null 2>&1; then
			missing_tools="$missing_tools $tool"
		fi
	done

	if [ -n "$missing_tools" ]; then
		echo "Missing required tools:$missing_tools"
		echo "Please install the missing tools and run make again."
		exit 1
	fi

	echo "All required tooling is installed (rg, shfmt, npx)"
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

	# Common packages across all distros
	default_packages="autoconf bc bison cpio cmake curl dialog file flex gawk git m4 make mtools nano parted patch perl rsync swig unzip wget ripgrep shfmt nodejs npm"

	# Resolve the distro family once. ID_LIKE catches the Debian derivatives
	# (Ubuntu, Mint, ...); Debian itself ships no ID_LIKE, so it can only be
	# matched by ID. Both paths must end up on the same package list.
	distro_family=""
	case "$ID_LIKE" in
		*debian*)
			echo "Detected as Debian-based via ID_LIKE"
			distro_family="debian"
			;;
	esac

	if [ -z "$distro_family" ]; then
		case "$ID" in
			ubuntu | debian | linuxmint | zorin)
				echo "Detected as Debian-based via ID"
				distro_family="debian"
				;;
			rhel | centos | fedora)
				echo "RedHat-based"
				distro_family="redhat"
				;;
			arch)
				echo "Arch-based"
				distro_family="arch"
				;;
			alpine)
				echo "Alpine Linux"
				distro_family="alpine"
				;;
			opensuse*)
				echo "OpenSUSE Tumbleweed"
				distro_family="suse"
				;;
			*)
				echo "Unsupported OS: $ID"
				exit 1
				;;
		esac
	fi

	# The python packages are per-family, not in default_packages, because Arch
	# names the interpreter "python" and ships its headers in that same package.
	# They are needed because U-Boot selects BINMAN -> DTOC -> PYLIBFDT, and
	# Buildroot is never asked for host-python3 (no BR2_TARGET_UBOOT_NEEDS_*),
	# so scripts/dtc/pylibfdt is swig-built against the distro python3 and needs
	# both Python.h and setuptools.
	case "$distro_family" in
		debian)
			pkg_manager="dpkg"
			pkg_check_command="dpkg-query -W -f='\${Status}'"
			pkg_install_cmd="apt-get install -y"
			pkg_update_cmd="apt-get update"
			packages="$default_packages build-essential ccache libcrypt-dev libncurses-dev libusb-1.0-0-dev u-boot-tools vim-tiny whiptail python3 python3-dev python3-setuptools python3-jsonschema"
			;;
		redhat)
			pkg_manager="rpm"
			pkg_check_command="rpm -q --whatprovides"
			pkg_install_cmd="dnf install -y"
			packages="$default_packages gcc libxcrypt-devel ncurses-devel newt libusbx-devel uboot-tools python3 python3-devel python3-setuptools python3-jsonschema"
			;;
		arch)
			pkg_manager="pacman"
			pkg_check_command="pacman -Q"
			pkg_install_cmd="pacman -S --noconfirm"
			packages="$default_packages base-devel libxcrypt libnewt ncurses uboot-tools python python-setuptools python-jsonschema"
			;;
		alpine)
			pkg_manager="apk"
			pkg_check_command="apk info -e"
			pkg_install_cmd="apk add"
			packages="$default_packages bash build-base findutils grep libusb-dev ncurses-dev newt uboot-tools python3 python3-dev py3-setuptools py3-jsonschema"
			;;
		suse)
			pkg_manager="zypper"
			pkg_check_command="zypper search -i"
			pkg_install_cmd="zypper install -y"
			packages="$default_packages gcc findutils grep libxcrypt-devel ncurses-devel newt libusb-1_0-devel u-boot-tools python3 python3-devel python3-setuptools python3-jsonschema"
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
				if ! $pkg_check_command "vim-tiny" 2>/dev/null | grep -q "install ok installed" &&
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
		if [ "$distro_family" = "debian" ]; then
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

check_required_tools

exit 0
