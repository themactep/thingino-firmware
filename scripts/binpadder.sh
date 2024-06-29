#!/bin/bash
#
# Binary file padder.
# Pads binary file with 0xFF to match full size of flashing chip.
#
# Example:
#   ./binpadder.sh u-boot-t10.bin 8
#
# Running this command will produce a new binary file
# u-boot-t10-8MB-padded.bin
# in the same directory as the original binary file.
#
# Paul Philippov <paul@themactep.com>
#

if [ $# -lt 2 ]; then
  echo "Usage: $0 <binary file> <flash chip size in MB>"
  exit 1
fi

case "$2" in
   8) flashsizemb="8MB"; flashsize=8388608 ;;
  16) flashsizemb="16MB"; flashsize=16777216 ;;
   *) echo "Unknown flash size. Use 8 or 16." && exit 2
esac

infile="$1"
[ ! -f "$infile" ] && echo "Cannot find input binary file." && exit 3
infilesize=$(wc -c $infile | awk '{print $1}')

[ "$infilesize" -gt "$flashsize" ] && echo "Binary file is larger than targeted flash size!" && exit 4

blankfile="${infile%.*}-${flashsizemb}-blank.bin"
dd if=/dev/zero bs="${flashsize}" skip=0 count=1 | tr '\000' '\377' > "${blankfile}"
dd if="${infile}" bs=1 skip=0 count=${infilesize} of="${blankfile}" conv=notrunc status=none
mv "${blankfile}" "${infile%.*}-${flashsizemb}-padded.bin"

exit 0
