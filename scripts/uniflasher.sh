#!/bin/sh
#
# Universal firmware installer.
# Run on an embedded device in Linux shell to install
# a full firmware image to a non-matching partitioning.
#
# Requires dd and flascp.
#
# 2024, Paul Philippov, paul@themactep.com

check_prereq() {
	command -v $1 > /dev/null && return
	echo "Cannot find $1."
	exit 1
}

check_prereq dd
check_prereq flashcp

firmware="$1"
if [ -z "$firmware" ]; then
	echo "Usage: $0 <path to firmware file>"
	exit 1
fi

mtd_num=0
needle=0
align_block=$((32 * 1024))
fw_size=$(cat $firmware | wc -c)

for size_hex in $(awk 'NR>1{print $2}' /proc/mtd); do
	[ "$needle" -ge "$fw_size" ] && break

	echo "mtd$mtd_num"
	echo "----------"
	partfile=/tmp/mtd${mtd_num}.bin

	echo " Extracting block of $size_dec bytes starting at $needle"
	size_dec=$((0x$size_hex))
	dd if=$firmware of=$partfile bs=$align_block skip=$((needle/align_block)) count=$((size_dec/align_block))

	echo " Flashing partition mtd${mtd_num}"
	flashcp -v $partfile /dev/mtd${mtd_num}

	rm $partfile
	needle=$((needle + size_dec))
	mtd_num=$((mtd_num + 1))
	echo
done

echo "Done. Please reboot."
exit 0
