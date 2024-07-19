#!/bin/bash
#
# Binary file padder.
# Pads binary file with 0xFF to a given size.
# Size can be given as bytes, or with a suffix:
# 16000, 256k, 8m
#
# Example:
# ./binpadder.sh u-boot-t10.bin 8M
#
# Paul Philippov <paul@themactep.com>

if [ $# -lt 2 ]; then
	echo "Usage: $0 <binary file> <final size>"
	exit 1
fi

unit=${2:0-1}
echo "SIZE: $2"
echo "UNIT: $unit"

case "$unit" in
	b | B | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 0)
		final_size=$2
		break
		;;
	k | K)
		final_size=$((${2::-1} * 1024))
		break
		;;
	m | M)
		final_size=$((${2::-1} * 1024 * 1024))
		break
		;;
	*)
		echo "$unit - Unknown unit"
		exit 2
		;;
esac

input_file="$1"
[ ! -f "$input_file" ] && echo "Cannot find input binary file." && exit 3

input_file_size=$(wc -c $input_file | awk '{print $1}')

[ "$input_file_size" -gt "$final_size" ] && echo "Binary file is larger than targeted flash size!" && exit 4

temp_file=$(mktemp)
dd if=/dev/zero bs=$final_size skip=0 count=1 | tr '\000' '\377' > $temp_file
dd if="$input_file" bs=1 skip=0 count=$input_file_size of=$temp_file conv=notrunc status=none
mv $temp_file "${input_file%.*}-$2-padded.bin"

exit 0
