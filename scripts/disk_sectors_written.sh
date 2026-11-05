#!/bin/sh
# Print the total number of sectors written to physical block devices.
# Physical means lsblk "disk" type, excluding RAM-backed virtual devices.
# SSD-wear proxy: bytes written = sectors * 512.

set -u

total=0
devs=$(lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" && $1 !~ /^(zram|ram|loop|nbd|pmem|fd|md)/ { print $1 }')
for dev in $devs; do
	sectors=$(awk -v d="$dev" '$3 == d { print $10 }' /proc/diskstats 2>/dev/null)
	total=$((total + ${sectors:-0}))
done
printf '%s\n' "$total"
