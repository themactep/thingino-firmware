#!/bin/bash
#
# Stitcher
#   a firmware file assembler for wehaveopencipathome project
#
# Usage:
#   ./stitcher.sh
#
# This script will produce a binary file autoupdate-full.bin
# suitable for updating an IPC from an SD card,
# or for programming a flash chip in a programmer.
#
# OTA update using ssh and an SD card:
#
#   scp -O firmware-1706958832.bin root@192.168.1.10:/mnt/mmcblk0p1/autoupdate-full.bin
#   ssh root@192.168.1.10 "rm /mnt/mmcblk0p1/autoupdate-full.done; reboot"
#
# 2024, Paul Philippov <paul@themactep.com>

echo "Analyzing files..."
echo
for i in *; do
	# is a file
	[ ! -f $i ] && continue
	# is not a symbolic link
	[ -L $i ] && continue
	magic=$(xxd -l4 -ps "$i")
	case "$magic" in
		06050403)
			[ "$(stat -c%s $i)" -gt "262144" ] && continue
			echo U-Boot: $i
			u_boot=$i
			;;
		27051956)
			echo Kernel: $i
			kernel=$i
			;;
		68737173)
			echo RootFS: $i
			rootfs=$i
			;;
		*)
			# do nothing
			;;
    esac
done
echo

[ -z "$u_boot" ] && echo Cannot find U-Boot. Aborting... && exit 2
[ -z "$kernel" ] && echo Cannot find Kernel. Aborting... && exit 3
[ -z "$rootfs" ] && echo Cannot find RootFS. Aborting... && exit 4

echo Found all required parts of the future firmware.
echo We are good to go!
echo Assembling...
echo

alignment=$((64 * 1024))

u_boot_offset=$((0x0))
u_boot_size=$(stat -c%s $u_boot)

kernel_offset=$((0x50000))
kernel_size=$(stat -c%s $kernel)
kernel_size_aligned=$(((kernel_size / alignment + 1) * alignment))

rootfs_offset=$((kernel_offset + kernel_size_aligned))
rootfs_size=$(stat -c%s $rootfs)
rootfs_size_aligned=$(( ($rootfs_size / $alignment + 1) * $alignment ))

tmpfile=$(mktemp)

#echo dd if=/dev/zero bs=8M skip=0 count=1 | tr '\000' '\377' > $tmpfile
dd if=/dev/zero bs=8M skip=0 count=1 2> /dev/null | tr '\000' '\377' > $tmpfile

#echo dd if=$u_boot bs=1 seek=$u_boot_offset count=$u_boot_size of=$tmpfile conv=notrunc status=none
dd if=$u_boot bs=1 seek=$u_boot_offset count=$u_boot_size of=$tmpfile conv=notrunc status=none

#echo dd if=$kernel bs=1 seek=$kernel_offset count=$kernel_size of=$tmpfile conv=notrunc status=none
dd if=$kernel bs=1 seek=$kernel_offset count=$kernel_size of=$tmpfile conv=notrunc status=none

#echo dd if=$rootfs bs=1 seek=$rootfs_offset count=$rootfs_size of=$tmpfile conv=notrunc status=none
dd if=$rootfs bs=1 seek=$rootfs_offset count=$rootfs_size of=$tmpfile conv=notrunc status=none

final_filename="firmware-$(date +%s).bin"
#echo mv $tmpfile $final_filename
mv $tmpfile $final_filename

echo Firmware file is $final_filename
printf "u-boot: 0x%08x - 0x%08x\n" $u_boot_offset $((u_boot_offset + u_boot_size))
printf "kernel: 0x%08x - 0x%08x\n" $kernel_offset $((kernel_offset + kernel_size_aligned))
printf "rootfs: 0x%08x - 0x%08x\n" $rootfs_offset $((rootfs_offset + rootfs_size_aligned))
ln -sf $final_filename autoupdate-full.bin
echo
echo "Done"
exit 0
