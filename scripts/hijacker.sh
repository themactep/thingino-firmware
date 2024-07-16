#!/bin/bash
#
# Embedded Linux root hijacker
#
# This script repacks firmware replacing existing root password with a blank password.
# Tested on HiSilicon and Ingenic firmware dumps from NOR SPI flash chips.
# Use at your own risk.
#
# Paul Philppov <paul@themactep.com>
# 2023-11-21: Initial release
# 2023-11-25: Handle hexadecimal values in mtdparts
# 2024-01-26: Use the last found copy of mtdparts
# 2024-02-14: Enable disabled console
# 2024-05-14: Fix false-positive matches
# 2024-07-08: Start telnet
# 2024-07-10: Refactor and colorize output

if [ -z "$1" ]; then
	echo "Usage: $0 <stock firmware dump>"
	exit 1
fi

echo_c() {
	echo -e "\e[38;5;$1m$2\e[0m"
}

die() {
	echo_c 124 "Error! $1"
	exit 1
}

run() {
	echo_c 94 "$1"
	eval $1
}

say() {
	echo_c 70 "\n$1"
}

full_binary_file="$1"

bootcmd=$(strings "$full_binary_file" | grep -E "mtdparts=\w+_sfc:" | tail -1)

root_part_num=$(echo $bootcmd | sed -E "s/(.*)(root=)/\\2/" | cut -d ' ' -f 1 | cut -d '=' -f 2 | sed -E "s/.*(.)/\\1/")

offset_bytes=0

say "looking for mtd partitions"
mtdparts=$(echo $bootcmd | sed -E "s/(.*)(mtdparts=)/\\2/" | cut -d ' ' -f 1 | cut -d: -f2)

say "Found this: $mtdparts"
for p in ${mtdparts//,/ }; do
	p_size=$(echo $p | cut -d '(' -f 1)

	if [ "-" = "$p_size" ]; then
		p_size_bytes=""
	elif [ "0x" = "${p_size:0:2}" ]; then
		## convert hex values
		p_size_bytes=$(( $p_size ))
	else
		p_size_value=$(echo $p_size | sed -E 's/[^0-9]//g')
		p_size_unit=$(echo $p_size | sed -E 's/[0-9]+//')
		if [ "k" = "${p_size_unit,,}" ]; then
			p_size_bytes=$(( p_size_value * 1024 ))
		elif [ "m" = "${p_size_unit,,}" ]; then
			p_size_bytes=$(( p_size_value * 1024 * 1024 ))
		else
			p_size_bytes=$p_size_value
		fi
	fi

	printf "%-14s\toffset: %8d\tsize: %8d\n" $p $offset_bytes $p_size_bytes
	if [ "$n" = "$root_part_num" ]; then
		echo "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"
		rootfs_file=rootfs.bin
		rootfs_offset=$offset_bytes
		rootfs_size=$p_size_bytes
	fi

	offset_bytes=$(( offset_bytes + p_size_bytes ))
	n=$(( n + 1 ))
done

say "extract rootfs partition from full dump: $rootfs_size bytes at offset $rootfs_offset"
run "dd if=$full_binary_file bs=1 skip=$rootfs_offset count=$rootfs_size of=$rootfs_file status=progress"

say "unpack rootfs partition"
run "unsquashfs $rootfs_file || die Unable to unpack rootfs!"

say "replace password"
run "echo \"root::0:0:root:/root:/bin/sh\" > $(find squashfs-root -name passwd | grep etc)"

say "enable console"
run "sed -i 's/^#console:/console:/'  $(find squashfs-root -name inittab | grep etc)"

say "activate telnet"
run "echo 'telnetd &' >> $(find squashfs-root -name rcS)"

say "repack rootfs partition"
new_rootfs_file="${rootfs_file}-patched"
run "mksquashfs squashfs-root $new_rootfs_file -comp xz"

say "make sure new rootfs fits the partition"
new_rootfs_size=$(stat -c %s "$new_rootfs_file")
[ $new_rootfs_size -gt $rootfs_size ] && die "repacked file is larger than available partition!"

say "echo make a patched copy of full binary"
new_full_binary_file="${full_binary_file}-patched"
run "cp $full_binary_file $new_full_binary_file"

say "assemble new firmware"
tmp_file=$(mktemp)

run "dd if=/dev/zero bs=$rootfs_size count=1 | tr '\000' '\377' > $tmp_file"
run "dd if=$tmp_file bs=1 seek=$rootfs_offset count=$rootfs_size of=$new_full_binary_file conv=notrunc status=progress"
run "dd if=$new_rootfs_file bs=1 seek=$rootfs_offset count=$new_rootfs_size of=$new_full_binary_file conv=notrunc status=progress"

say "clean up the mess"
#run "rm -rf squashfs-root"
run "rm -rf $rootfs_file"
run "rm -rf $new_rootfs_file"
run "rm -f $tmp_file"

say "Done!"

exit 0
