#!/bin/bash
#
# Binary file compiler for flex image.
# Creates a file for programming onto a flash chip.
#
# Example:
#   ./compile4programmer.sh uboot.bin uImage rootfs.squashfs 8
#
# Running this command will produce a new binary file
# full4programmer-8MB.bin or full4programmer-16MB.bin
# suitable for flashing with a programmer.
#
# 2023, Paul Philippov <paul@themactep.com>
#

if [ $# -lt 4 ]; then
  echo "Usage: $0 <uboot.bin> <kernel.bin> <rootfs.bin> <flash chip size in MB>"
  exit 1
fi

case "$4" in
    8)
        flashsizemb="8MB"
        flashsize=$((0x800000))
        ;;
    16)
        flashsizemb="16MB"
        flashsize=$((0x1000000))
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

alignment=$((32 * 1024))

u_boot_offset=$((0x0))
u_boot_size=$(stat -c%s $u_boot)

kernel_offset=$((0x50000))
kernel_size=$(stat -c%s $kernel)
kernel_size_aligned=$(( ($kernel_size / $alignment + 1) * $alignment ))

rootfs_offset=$(( $kernel_offset + $kernel_size_aligned ))
rootfs_size=$(stat -c%s $rootfs)
rootfs_size_aligned=$(( ($rootfs_size / $alignment + 1) * $alignment ))

tmpfile=$(mktemp)

dd if=/dev/zero bs="$flashsize" skip=0 count=1 | tr '\000' '\377' > $tmpfile
dd if=$u_boot bs=1 seek=$u_boot_offset count=$u_boot_size of=$tmpfile conv=notrunc status=none
dd if=$kernel bs=1 seek=$kernel_offset count=$kernel_size of=$tmpfile conv=notrunc status=none
dd if=$rootfs bs=1 seek=$rootfs_offset count=$rootfs_size of=$tmpfile conv=notrunc status=none
mv $tmpfile "full4programmer-${flashsizemb}-flex.bin"

printf "u-boot: 0x%08x - 0x%08x\n" $u_boot_offset $(( $u_boot_offset + $u_boot_size ))
printf "kernel: 0x%08x - 0x%08x\n" $kernel_offset $(( $kernel_offset + $kernel_size_aligned ))
printf "rootfs: 0x%08x - 0x%08x\n" $rootfs_offset $(( $rootfs_offset + $rootfs_size_aligned ))

echo "Done"
exit 0
