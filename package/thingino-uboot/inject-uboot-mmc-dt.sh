#!/bin/sh
# Inject per-board MMC + button device-tree properties into a U-Boot leaf .dts at
# build time, read from the board's thingino.json. These GPIOs are board-specific
# while the U-Boot device tree is per-SoC, so they cannot live in the shared .dts
# and are appended to this board's build copy instead:
#
#   - vmmc-supply : a regulator-fixed gated by gpio.mmc_power, so the mmc core
#                   powers the slot itself (any SoC - it just drives a gpio).
#   - cd-gpios    : native card-detect, only on SoCs whose gpio driver applies
#                   pull-up bias (T23 and everything from T31 on); others keep
#                   the plain probe behaviour.
#   - gpio-keys   : a "reset" button from gpio.button_reset, so CONFIG_BUTTON_CMD
#                   runs "button_cmd_0" (factory reset) when it is held at boot.
#
# Numeric gpio flags are emitted (ACTIVE_LOW=1/PULL_UP=0x10) so the fragment
# needs no dt-bindings include - not every SoC .dts pulls in gpio.h.
#
# Usage: inject-uboot-mmc-dt.sh <thingino.json> <leaf.dts> <dt-name>
set -e

JSON="$1"; DTS="$2"; DT="$3"
[ -f "$JSON" ] && [ -f "$DTS" ] || exit 0

# Read gpio.mmc_cd, gpio.mmc_power.{pin,active_low} and gpio.button_reset in one
# shot. python3 is already a U-Boot build dependency (binman), so this needs no
# host package.
vals=$(python3 - "$JSON" 2>/dev/null <<'PY'
import json, sys
g = json.load(open(sys.argv[1])).get("gpio", {})
cd = g.get("mmc_cd")
mp = g.get("mmc_power")
pin = mp.get("pin") if isinstance(mp, dict) else None
al = mp.get("active_low") if isinstance(mp, dict) else None
br = g.get("button_reset")
bp = br.get("pin") if isinstance(br, dict) else (br if isinstance(br, int) else None)
print(cd if isinstance(cd, int) else -1,
      pin if isinstance(pin, int) else -1,
      1 if al else 0,
      bp if isinstance(bp, int) else -1)
PY
)
[ -n "$vals" ] || exit 0
# shellcheck disable=SC2086
set -- $vals
CD=$1; PWR=$2; AL=$3; BTN=$4

# gpio number -> bank label letter (PA=a..PE=e), empty if out of range
bank() {
	case $(( $1 / 32 )) in
	0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

# ---- vmmc-supply: slot power, any SoC -------------------------------------
if [ "$PWR" -ge 0 ] && ! grep -q 'vmmc-supply' "$DTS"; then
	PB=$(bank "$PWR")
	if [ -n "$PB" ]; then
		if [ "$AL" = 1 ]; then POL=1; EAH=0; else POL=0; EAH=1; fi
		{
			printf '\n/ {\t/* MMC slot power, board gpio.mmc_power.pin=%s */\n' "$PWR"
			printf '\tvcc_mmc: regulator-mmc {\n'
			printf '\t\tcompatible = "regulator-fixed";\n'
			printf '\t\tregulator-name = "mmc-vcc";\n'
			printf '\t\tgpio = <&gp%s %s %s>;\n' "$PB" "$(( PWR % 32 ))" "$POL"
			[ "$EAH" = 1 ] && printf '\t\tenable-active-high;\n'
			printf '\t\tstartup-delay-us = <100000>;\n'
			printf '\t};\n};\n&msc0 {\n\tvmmc-supply = <&vcc_mmc>;\n};\n'
		} >> "$DTS"
		echo "U-Boot: injected vmmc-supply = <&gp$PB $(( PWR % 32 ))> (gpio $PWR)"
	fi
fi

# ---- cd-gpios: card-detect (any board that wires a detect line) -----------
# The PULL_UP flag is honoured by the gpio driver's set_flags only on the
# split-pull SoCs (T23 and T31 on); the older SoCs keep their board's own pull,
# which is how their card-detect already worked.
if [ "$CD" -ge 0 ] && ! grep -q 'cd-gpios' "$DTS"; then
	CB=$(bank "$CD")
	if [ -n "$CB" ]; then
		{
			printf '\n&msc0 {\t/* MMC card-detect, board gpio.mmc_cd=%s */\n' "$CD"
			printf '\t/delete-property/ broken-cd;\n'
			printf '\tcd-gpios = <&gp%s %s 0x11>;\t/* GPIO_ACTIVE_LOW | GPIO_PULL_UP */\n' "$CB" "$(( CD % 32 ))"
			printf '};\n'
		} >> "$DTS"
		echo "U-Boot: injected cd-gpios = <&gp$CB $(( CD % 32 ))> (gpio $CD)"
	fi
fi

# ---- gpio-keys: factory-reset button --------------------------------------
# CONFIG_BUTTON_CMD checks this once early in main_loop and runs "button_cmd_0"
# if the button labelled "reset" is held. Active-low with pull-up, same bias
# handling as cd-gpios (pull-up honoured on T23 and T31 on; older SoCs keep the
# board's own pull, which is how the reset line already read).
if [ "$BTN" -ge 0 ] && ! grep -q 'gpio-keys' "$DTS"; then
	BB=$(bank "$BTN")
	if [ -n "$BB" ]; then
		{
			printf '\n/ {\t/* factory-reset button, board gpio.button_reset=%s */\n' "$BTN"
			printf '\tgpio-keys {\n'
			printf '\t\tcompatible = "gpio-keys";\n'
			printf '\t\treset {\n'
			printf '\t\t\tlabel = "reset";\n'
			printf '\t\t\tgpios = <&gp%s %s 0x11>;\t/* GPIO_ACTIVE_LOW | GPIO_PULL_UP */\n' "$BB" "$(( BTN % 32 ))"
			printf '\t\t\tlinux,code = <0x198>;\t/* KEY_RESTART */\n'
			printf '\t\t};\n'
			printf '\t};\n'
			printf '};\n'
		} >> "$DTS"
		echo "U-Boot: injected gpio-keys reset = <&gp$BB $(( BTN % 32 ))> (gpio $BTN)"
	fi
fi
exit 0
