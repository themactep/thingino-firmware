#!/bin/sh
# Inject this board's wired-Ethernet PHY reset line into a U-Boot leaf .dts at
# build time, read from the board's thingino.json gpio.eth_phy_reset key.
#
# U-Boot's dwmac_ingenic driver (2026.07 tree) probes &gmac at every boot,
# brings up the MAC-PHY clock and RMII pinmux, then - when the node carries
# ingenic,reset-gpio - requests that line and pulses it (10 ms deasserted,
# 50 ms asserted, 10 ms settled, polarity from the DT active-level flag)
# before the MDIO BMCR soft-reset. The external-RMII .dtsi can only carry
# the ISVP reference default (PB28 = gpio 60, active-low) - right for a
# reference board and wrong for most cameras, and boards with no reset line
# wired at all depend on the MDIO soft-reset fallback (a GPIO pointing at
# an unrelated pin would actively break them). This overrides it per board:
#
#   gpio.eth_phy_reset present - ingenic,reset-gpio is rewritten to that pin
#                 and polarity. Short notation, same as the rest of the gpio
#                 section: a bare int is an active-low pin (the reset line
#                 rests high on these boards - see the legacy
#                 BR2_PACKAGE_THINGINO_UBOOT_GPIO_PHY_RESET_ENLEVEL=0
#                 boards), an object {"pin": N, "active_low": false} an
#                 active-high one.
#
#   gpio.eth_phy_reset absent - the .dts is left alone, so the inherited
#                 per-SoC default (or its per-board absence) stands.
#
# A numeric gpio flag is emitted (ACTIVE_LOW=1) so the fragment needs no
# dt-bindings include - not every SoC .dts pulls in gpio.h.
#
# Usage: inject-uboot-eth-dt.sh <thingino.json> <leaf.dts> <dt-name>
set -e

JSON="$1"
DTS="$2"
DT="$3"
[ -f "$JSON" ] && [ -f "$DTS" ] || exit 0

# Already injected on a previous incremental build?
grep -q 'thingino eth phy reset' "$DTS" && exit 0

# Not every SoC has a GMAC node to override, and the label lives in an
# included per-SoC .dtsi rather than the leaf. Walk the include chain and
# leave the .dts alone when there is no gmac: label in it.
DTSDIR=$(dirname "$DTS")
chain="$DTS"
next="$DTS"
depth=0
while [ -n "$next" ] && [ "$depth" -lt 5 ]; do
	# shellcheck disable=SC2086
	inc=$(sed -n 's/^[[:space:]]*#include[[:space:]]*"\([^"]*\)".*/\1/p' $next 2>/dev/null | sort -u)
	found=""
	for f in $inc; do
		[ -f "$DTSDIR/$f" ] || continue
		case " $chain " in
			*" $DTSDIR/$f "*) continue ;;
		esac
		chain="$chain $DTSDIR/$f"
		found="$found $DTSDIR/$f"
	done
	next=$found
	depth=$((depth + 1))
done
# shellcheck disable=SC2086
grep -q '^[[:space:]]*gmac:' $chain || exit 0

# Emit "<pin> <active_low>".
vals=$(
	python3 - "$JSON" 2>/dev/null <<'PY'
import json, sys

g = json.load(open(sys.argv[1])).get("gpio", {})
e = g.get("eth_phy_reset")
if isinstance(e, dict):
    pin, al = e.get("pin"), e.get("active_low")
elif isinstance(e, int) and not isinstance(e, bool):
    pin, al = e, True	# short notation: bare int = active-low reset line
else:
    pin, al = None, None
if isinstance(pin, str) and pin.isdigit():
    pin = int(pin)
ok = isinstance(pin, int) and not isinstance(pin, bool) and pin >= 0
print(pin if ok else -1, 1 if (ok and al) else 0)
PY
)
[ -n "$vals" ] || exit 0
# shellcheck disable=SC2086
set -- $vals
PIN=$1
AL=$2
[ "$PIN" -ge 0 ] || exit 0

# gpio number -> bank label letter (PA=a..PE=e), empty if out of range
bank() {
	case $(($1 / 32)) in
		0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

PB=$(bank "$PIN")
[ -n "$PB" ] || {
	echo "U-Boot: gpio.eth_phy_reset pin $PIN out of range, leaving DT alone"
	exit 0
}

if [ "$AL" = 1 ]; then
	POL="1"
	POLNAME="GPIO_ACTIVE_LOW"
else
	POL="0"
	POLNAME="GPIO_ACTIVE_HIGH"
fi
{
	printf '\n&gmac {\t/* thingino eth phy reset, board gpio.eth_phy_reset=%s */\n' "$PIN"
	printf '\tingenic,reset-gpio = <&gp%s %s %s>;\t/* %s */\n' "$PB" "$((PIN % 32))" "$POL" "$POLNAME"
	printf '};\n'
} >>"$DTS"
echo "U-Boot: injected ingenic,reset-gpio = <&gp$PB $((PIN % 32)) $POL> (gpio $PIN, dt $DT)"

exit 0
