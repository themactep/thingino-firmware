#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: generate_kernel_led_header.sh <buildroot.config> <output.h>" >&2
	exit 1
fi

SOURCE="$1"
TARGET="$2"

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

led_count=0
led_records=""

append_led() {
	record="$1"
	if [ -z "$led_records" ]; then
		led_records="$record"
	else
		led_records="${led_records}
${record}"
	fi
	led_count=$((led_count + 1))
}

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

	case "$color" in
	B) led_name="led_b" ;;
	G) led_name="led_g" ;;
	R) led_name="led_r" ;;
	V) led_name="led_v" ;;
	W) led_name="led_w" ;;
	Y) led_name="led_y" ;;
	esac

	append_led "${led_name}|${gpio_value}|${active_low}"
done

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
