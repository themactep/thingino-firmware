#!/bin/bash
#
# Binary file compiler.
# Creates a file for programming onto a flash chip.
#
# Example:
#   ./compile4programmer.sh stock-uboot.bin uImage.t31 rootfs.squashfs.t31 8
#
# Running this command will produce a new binary file
# full4programmer-8MB.bin or full4programmer-16MB.bin
# suitable for flashing with a programmer.
#
# Paul Philippov <paul@themactep.com>
#

if [ $# -lt 4 ]; then
	echo "Usage: $0 <uboot.bin> <kernel.bin> <rootfs.bin> <flash chip size in MB>"
	exit 1
fi

case "$4" in
	8)
		flashsizemb="8MB"
		flashsize=$((0x800000))
		kernel_offset=$((0x50000))
		rootfs_offset=$((0x250000))
		;;
	16)
		flashsizemb="16MB"
		flashsize=$((0x1000000))
		kernel_offset=$((0x50000))
		rootfs_offset=$((0x350000))
		;;
	*)
		echo "Unknown flash size. Use 8 or 16."
		exit 2
esac

check_file() {
	if [ ! -f "$1" ]; then
		echo "File $1 not found."
		exit 3
	fi
}

u_boot=$1; check_file $u_boot
kernel=$2; check_file $kernel
rootfs=$3; check_file $rootfs

u_boot_size=$(stat -c%s $u_boot)
kernel_size=$(stat -c%s $kernel)
rootfs_size=$(stat -c%s $rootfs)

tmpfile=$(mktemp)

dd if=/dev/zero bs="$flashsize" skip=0 count=1 | tr '\000' '\377' > $tmpfile
dd if=$u_boot bs=1 seek=0 count=$u_boot_size of=$tmpfile conv=notrunc status=none
dd if=$kernel bs=1 seek=$kernel_offset count=$kernel_size of=$tmpfile conv=notrunc status=none
dd if=$rootfs bs=1 seek=$rootfs_offset count=$rootfs_size of=$tmpfile conv=notrunc status=none
mv $tmpfile "full4programmer-${flashsizemb}.bin"

echo "Done"
exit 0
