#!/bin/sh
# Print the MMC card-detect gpio number from a camera's device-tree fragment,
# or nothing when the fragment has no card-detect line.
#
# The fragment is the single source for the card-detect pin: the 4.4+ kernel
# takes it from the device tree, and both S09mmc's jzmmc cd_gpio_pin parameter
# and the U-Boot injection take it from here.
#
# Usage: mmc_cd_pin.sh <camera.dtsi>

set -eu

DTSI="${1:-}"
[ -n "$DTSI" ] && [ -f "$DTSI" ] || exit 0

awk '
	/ingenic,cd-gpios[ \t]*=/ {
		for (i = 1; i <= NF; i++) {
			if ($i ~ /&gp[a-e]/) {
				token = $i
				sub(/.*&gp/, "", token)
				bank = substr(token, 1, 1)
			} else if ($i ~ /^[0-9]+$/) {
				pin = $i
			}
		}
	}
	END {
		if (bank == "")
			exit 0
		printf "%d\n", (index("abcde", bank) - 1) * 32 + pin
	}
' "$DTSI"
