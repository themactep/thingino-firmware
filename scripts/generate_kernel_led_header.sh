#!/bin/sh
# shellcheck disable=SC2086
# Generate the 3.10 gpio-leds board header for the current build.
#
# The camera's device-tree fragment (.dtsi) is the source when it carries a
# gpio-leds node - the same definition the 4.4+ kernel consumes from DT, so
# both kernel lines then share one source. When no fragment is present, or it
# has no LEDs, fall back to the legacy BR2_THINGINO_LED_* values in the
# buildroot .config, so a profile can migrate one at a time.
#
# Usage: generate_kernel_led_header.sh <buildroot.config> <output.h> [camera.dtsi]

set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
	echo "usage: generate_kernel_led_header.sh <buildroot.config> <output.h> [camera.dtsi]" >&2
	exit 1
fi

SOURCE="$1"
TARGET="$2"
DTSI="${3:-}"

get_value() {
	key="$1"
	if [ ! -f "$SOURCE" ]; then
		return 0
	fi

	value=$(sed -n "s/^${key}=//p" "$SOURCE" | head -n1)
	value=${value#\"}
	value=${value%\"}
	printf '%s' "$value"
}

is_integer() {
	printf '%s\n' "$1" | grep -Eq '^-?[0-9]+$'
}

led_records=""

# Preferred source: the camera's gpio-leds node.
if [ -n "$DTSI" ] && [ -f "$DTSI" ]; then
	led_records=$(
		python3 - "$DTSI" <<'PY'
import re
import sys

src = open(sys.argv[1]).read()


def block(src, name):
    m = re.search(r'^[ \t]*%s[ \t]*\{' % re.escape(name), src, re.M)
    if not m:
        return None
    depth, start = 0, src.index("{", m.start())
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
    return None


base = {"a": 0, "b": 32, "c": 64, "d": 96, "e": 128}
leds = block(src, "gpio-leds")
if leds is not None:
    for child in re.finditer(r'([A-Za-z0-9_\-]+)[ \t]*\{([^{}]*)\}', leds):
        name, body = child.group(1), child.group(2)
        label = re.search(r'label[ \t]*=[ \t]*"([^"]+)"', body)
        gpio = re.search(r'(?:^|[ \t])gpios[ \t]*=[ \t]*<[ \t]*&(gp[a-e])[ \t]+(\d+)[ \t]+(\S+)', body, re.M)
        if not gpio:
            continue
        bank, pin, flag = gpio.group(1), int(gpio.group(2)), gpio.group(3)
        print("%s|%d|%s" % (label.group(1) if label else name,
                            base[bank[-1]] + pin,
                            "1" if "GPIO_ACTIVE_LOW" in flag else "0"))
PY
	)
fi

# Fallback: the legacy BR2_THINGINO_LED_* values in the buildroot .config.
if [ -z "$led_records" ]; then
	for color in B G R V W Y; do
		gpio_value=$(get_value "BR2_THINGINO_LED_${color}_GPIO")
		[ -n "$gpio_value" ] || gpio_value="-1"

		if ! is_integer "$gpio_value"; then
			continue
		fi

		if [ "$gpio_value" -lt 0 ]; then
			continue
		fi

		active_low=0
		if [ "$(get_value "BR2_THINGINO_LED_${color}_ACTIVE_LOW")" = "y" ]; then
			active_low=1
		fi

		led_name="led_$(printf '%s' "$color" | tr '[:upper:]' '[:lower:]')"
		if [ -z "$led_records" ]; then
			led_records="${led_name}|${gpio_value}|${active_low}"
		else
			led_records="${led_records}
${led_name}|${gpio_value}|${active_low}"
		fi
	done
fi

led_count=0
if [ -n "$led_records" ]; then
	led_count=$(printf '%s\n' "$led_records" | grep -c .)
fi

mkdir -p "$(dirname "$TARGET")"

{
	printf '%s\n' "#ifndef __THINGINO_GENERATED_LEDS_H__"
	printf '%s\n' "#define __THINGINO_GENERATED_LEDS_H__"
	printf '\n'
	printf '%s\n' "#define THINGINO_GPIO_LEDS_COUNT ${led_count}"
	printf '\n'
	printf '%s\n' "#define THINGINO_GPIO_LEDS_ITEMS \\"

	if [ "$led_count" -gt 0 ]; then
		index=1
		OLD_IFS=$IFS
		IFS='
'
		for record in $led_records; do
			IFS='|'
			set -- $record
			IFS='
'
			name="$1"
			pin="$2"
			active_low="$3"
			suffix=""
			if [ "$index" -lt "$led_count" ]; then
				suffix=" \\"
			fi

			printf '\t{ .name = "%s", .gpio = %s, .active_low = %s, .default_state = %s },%s\n' \
				"$name" "$pin" "$active_low" "LEDS_GPIO_DEFSTATE_OFF" "$suffix"
			index=$((index + 1))
		done
		IFS=$OLD_IFS
	else
		printf '\t/* no generated LEDs */\n'
	fi

	printf '\n'
	printf '%s\n' "#endif"
	printf '\n'
} >"$TARGET"
