#!/bin/sh
# Fail if a jffs2 data image contains JFFS2 cleanmarker nodes.
#
# The data image is built with --no-cleanmarkers so that empty padded blocks
# are all-0xFF and jffs2 erases them at the first mount with the erase size
# the kernel reports. A cleanmarker baked into the image at a different
# erase size (e.g. 32 KiB markers on a kernel with 64 KiB blocks) sits in the
# middle of a block that jffs2 assumes clean; the next write over it ANDs the
# marker into the data and the node fails its data CRC (EIO on read).
#
# A cleanmarker is magic 0x1985, nodetype 0x2003, totlen 12 (little endian):
# 85 19 03 20 0c 00 00 00. Nodes are 4-byte aligned in the image.
set -e
img="$1"
[ -f "$img" ] || { echo "check-jffs2-cleanmarkers: no image '$img'" >&2; exit 1; }
# 8-byte words read from offset 0 and from offset 4 cover every 4-aligned slot
hits=0
for skip in 0 4; do
	c=$(od -An -v -tx1 -w8 -j$skip "$img" | tr -d ' ' | grep -c '^851903200c000000$' || true)
	hits=$((hits + c))
done
if [ "$hits" -ne 0 ]; then
	echo "check-jffs2-cleanmarkers: $img has $hits cleanmarker(s); build it with --no-cleanmarkers" >&2
	exit 1
fi
echo "check-jffs2-cleanmarkers: $img OK (no cleanmarkers)"
