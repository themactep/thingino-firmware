#!/bin/sh
# Inject PTZ motor coil-park gpio-hogs into a U-Boot leaf .dts at build time,
# read from the board's thingino.json "motors" section.
#
# On a PTZ camera the pan/tilt stepper phase lines drive a Darlington array
# (e.g. ULN2803) that sinks coil current. From power-on until the Linux motor
# driver loads and parks them, any phase pin left at its energised level holds
# a coil powered - the coils cook. The kernel driver parks them at module load
# (motor_power_off); this closes the boot-window gap by hogging the same pins
# at the same de-energised level in U-Boot.
#
# The park level mirrors the kernel's rule (motor.c): with gpio_invert=false
# the driver cuts power by driving LOW, with gpio_invert=true by driving HIGH.
# So: invert=false -> output-low, invert=true -> output-high. Flags are emitted
# as GPIO_ACTIVE_HIGH (0) so the physical level is unambiguous and no
# dt-bindings include is needed.
#
# Only wired (non-SPI) stepper phases are hogged; is_spi motors and focus-only
# (VCM) boards have no coil phase GPIOs and are skipped.
#
# Usage: inject-uboot-motor-dt.sh <thingino.json> <leaf.dts> <dt-name>
set -e

JSON="$1"; DTS="$2"; DT="$3"
[ -f "$JSON" ] && [ -f "$DTS" ] || exit 0

# Already injected on a previous incremental build?
grep -q 'motor coil-park' "$DTS" && exit 0

# Emit: "<invert> <pin> <pin> ..." - invert flag then every pan+tilt phase pin,
# or nothing at all when there is nothing to park.
vals=$(python3 - "$JSON" 2>/dev/null <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("motors", {})
if str(m.get("is_spi")).lower() == "true":
    sys.exit(0)
pins = []
for axis in ("gpio_pan", "gpio_tilt"):
    v = m.get(axis)
    if isinstance(v, str):
        pins += [int(t) for t in v.split() if t.lstrip("-").isdigit() and int(t) >= 0]
    elif isinstance(v, int) and v >= 0:
        pins.append(v)
if not pins:
    sys.exit(0)
invert = 1 if str(m.get("gpio_invert")).lower() == "true" else 0
print(invert, " ".join(str(p) for p in pins))
PY
)
[ -n "$vals" ] || exit 0
# shellcheck disable=SC2086
set -- $vals
INVERT=$1; shift

# invert -> park level: false(0)=LOW=output-low, true(1)=HIGH=output-high
if [ "$INVERT" = 1 ]; then STATE="output-high"; else STATE="output-low"; fi

# gpio number -> bank label letter (PA=a..PE=e), empty if out of range
bank() {
	case $(( $1 / 32 )) in
	0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

emitted=""
{
	printf '\n/* PTZ motor coil-park: hold stepper phases de-energised until the\n'
	printf ' * kernel motor driver loads (board thingino.json motors section). */\n'
	for PIN in "$@"; do
		PB=$(bank "$PIN")
		[ -n "$PB" ] || continue
		printf '&gp%s {\n' "$PB"
		printf '\tmotor_park_%s {\n' "$PIN"
		printf '\t\tgpio-hog;\n'
		printf '\t\t%s;\n' "$STATE"
		printf '\t\tgpios = <%s 0>;\t/* GPIO_ACTIVE_HIGH */\n' "$(( PIN % 32 ))"
		printf '\t};\n'
		printf '};\n'
		emitted="$emitted $PIN"
	done
} >> "$DTS"

[ -n "$emitted" ] && echo "U-Boot: injected motor coil-park ($STATE) pins:$emitted"
exit 0
