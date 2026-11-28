#!/bin/sh
# Inject this board's speaker-amp enable line into a U-Boot leaf .dts at build
# time, read from the board's thingino.json gpio.speaker key.
#
# U-Boot's jz_t10_codec driver takes the amp enable gpio from the codec node's
# ingenic,spk-gpio property and drives it around PIO playback (the `sound`
# command), muted first and asserted last so the amp does not pop. The device
# tree is per-SoC while the pin is per-board, so the per-SoC .dtsi can only
# carry the ISVP reference default (PB31 = gpio 63, active-high) - right for a
# reference board and wrong for most cameras. This overrides it per board:
#
#   gpio.speaker present - ingenic,spk-gpio is rewritten to that pin and
#                 polarity. Short notation, same as the rest of the gpio
#                 section: a bare int is an active-high pin, an object
#                 {"pin": N, "active_low": true} an active-low one.
#
#   gpio.speaker absent - the inherited default is DELETED. Without this the
#                 board would drive gpio 63 on a `sound`, and on a board that
#                 has no amp there that pin belongs to something else.
#
# The same key drives the kernel module's spk_gpio/spk_level parameters, see
# INSTALL_AUDIO_SUPPORT in package/ingenic-sdk/ingenic-sdk.mk, and the
# boot-window mute hog in inject-uboot-gpio-dt.sh.
#
# A numeric gpio flag is emitted (ACTIVE_LOW=1) so the fragment needs no
# dt-bindings include - not every SoC .dts pulls in gpio.h.
#
# Usage: inject-uboot-audio-dt.sh <thingino.json> <leaf.dts> <dt-name>
set -e

JSON="$1"
DTS="$2"
DT="$3"
[ -f "$JSON" ] && [ -f "$DTS" ] || exit 0

# Already injected on a previous incremental build?
grep -q 'thingino speaker amp' "$DTS" && exit 0

# Not every SoC has an on-chip codec node to override (T33 has none), and the
# label lives in an included per-SoC .dtsi rather than the leaf. Walk the
# include chain and leave the .dts alone when there is no codec: label in it.
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
grep -q '^[[:space:]]*codec:' $chain || exit 0

# Emit "<pin> <active_low>", pin -1 when the board has no amp enable line.
vals=$(
	python3 - "$JSON" 2>/dev/null <<'PY'
import json, sys

g = json.load(open(sys.argv[1])).get("gpio", {})
s = g.get("speaker")
if isinstance(s, dict):
    pin, al = s.get("pin"), s.get("active_low")
elif isinstance(s, int) and not isinstance(s, bool):
    pin, al = s, False	# short notation: bare int = active-high pin
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

# gpio number -> bank label letter (PA=a..PE=e), empty if out of range
bank() {
	case $(($1 / 32)) in
		0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

PB=""
[ "$PIN" -ge 0 ] && PB=$(bank "$PIN")

if [ -n "$PB" ]; then
	if [ "$AL" = 1 ]; then
		POL="1"
		POLNAME="GPIO_ACTIVE_LOW"
	else
		POL="0"
		POLNAME="GPIO_ACTIVE_HIGH"
	fi
	{
		printf '\n&codec {\t/* thingino speaker amp, board gpio.speaker=%s */\n' "$PIN"
		printf '\tingenic,spk-gpio = <&gp%s %s %s>;\t/* %s */\n' "$PB" "$((PIN % 32))" "$POL" "$POLNAME"
		printf '};\n'
	} >>"$DTS"
	echo "U-Boot: injected ingenic,spk-gpio = <&gp$PB $((PIN % 32)) $POL> (gpio $PIN)"
else
	{
		printf '\n&codec {\t/* thingino speaker amp: this board has none */\n'
		printf '\t/delete-property/ ingenic,spk-gpio;\n'
		printf '};\n'
	} >>"$DTS"
	echo "U-Boot: no gpio.speaker - dropped the inherited ingenic,spk-gpio default"
fi

exit 0
