#!/bin/sh
# Guard files that are intentionally duplicated across package trees.
#
# Each line is a label followed by one or more paths separated by '|'.  All
# paths on a line must stay byte-identical.  If two copies diverge on purpose,
# remove or split the line and say why; if a package is added or removed,
# update the list.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
failed=0

while IFS= read -r line; do
	case "$line" in
		'' | '#'*) continue ;;
	esac

	old_ifs=$IFS
	IFS='|'
	set -f
	# shellcheck disable=SC2086  # split the manifest line on '|'
	set -- $line
	set +f
	IFS=$old_ifs

	label=${1:-}
	if [ "$#" -lt 2 ]; then
		echo "BAD MANIFEST: $label" >&2
		failed=1
		continue
	fi
	shift
	ref=$1
	shift

	if [ ! -f "$root/$ref" ]; then
		echo "MISSING: $label: $ref" >&2
		failed=1
		continue
	fi

	for path in "$@"; do
		if [ ! -f "$root/$path" ]; then
			echo "MISSING: $label: $path" >&2
			failed=1
		elif ! cmp -s "$root/$ref" "$root/$path"; then
			echo "DRIFT: $label: $path differs from $ref" >&2
			failed=1
		fi
	done
done <<'EOF'
bcm43438a1-syn-b43|package/wifi-syn4343/files/fw_bcm43438a1.bin|package/wifi-bcm43438/files/fw_bcm43438a1.bin|package/wifi-b43/files/fw_bcm43438a1.bin
bcm43438a1-bcmdhd|package/wifi-bcmdhd-ap6214a/files/fw_bcm43438a1.bin|package/wifi-bcmdhd-ap6181/files/fw_bcm43438a1.bin
bcm43436b0|package/wifi-syn4343/files/fw_bcm43436b0.bin|package/wifi-b43/files/fw_bcm43436b0.bin
usb-ocea|package/wifi-atbm6162u/files/firmware_usb_ocea.bin|package/wifi-atbm6132cu/files/firmware_usb_ocea.bin
ssv6x5x-cfg|package/wifi-ssv6x5x/files/ssv6x5x-wifi.cfg|package/wifi-ssv6158/files/ssv6x5x-wifi.cfg
phy-reg-pg|package/wifi-rtl8189fs/files/PHY_REG_PG.txt|package/wifi-rtl8189es/files/PHY_REG_PG.txt
nv-bcm43438a1|package/wifi-bcm43438/files/nv_bcm43438a1.txt|package/wifi-b43/files/nv_bcm43438a1.txt
lzma|package/linux/files/5.15.170/scripts/ingenic_hardlzma/lzma|package/linux/files/4.4.94/t32/scripts/ingenic_hardlzma/lzma
ingenic-mkimage|package/linux/files/5.15.170/scripts/ingenic_hardlzma/ingenic_mkimage|package/linux/files/4.4.94/t41/scripts/ingenic_hardlzma/ingenic_mkimage|package/linux/files/4.4.94/t32/scripts/ingenic_hardlzma/ingenic_mkimage
EOF

if [ "$failed" -ne 0 ]; then
	echo "Intentionally duplicated files are out of sync." >&2
	exit 1
fi
echo "Intentionally duplicated files are in sync."
