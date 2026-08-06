#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: patch_kernel_i2c1_gpio_pins.sh <buildroot.config> <board.h>" >&2
	exit 1
fi

SOURCE="$1"
BOARD_H="$2"

get_value() {
	key="$1"
	[ -f "$SOURCE" ] || return 0
	sed -n "s/^${key}=//p" "$SOURCE" | head -n1
}

[ -f "$BOARD_H" ] || exit 0
[ "$(get_value BR2_PACKAGE_THINGINO_KOPT_I2C_BUS1_GPIO)" = "y" ] || exit 0

sda=$(get_value BR2_THINGINO_I2C1_GPIO_SDA)
scl=$(get_value BR2_THINGINO_I2C1_GPIO_SCL)

case "$sda" in '' | *[!0-9]*) exit 0 ;; esac
case "$scl" in '' | *[!0-9]*) exit 0 ;; esac

gpio_macro() {
	n="$1"
	bank_idx=$((n / 32))
	offset=$((n % 32))
	case "$bank_idx" in
		0) bank=A ;;
		1) bank=B ;;
		2) bank=C ;;
		3) bank=D ;;
		*)
			echo "unsupported gpio bank for gpio $n" >&2
			exit 1
			;;
	esac
	printf 'GPIO_P%s(%d)' "$bank" "$offset"
}

sda_macro=$(gpio_macro "$sda")
scl_macro=$(gpio_macro "$scl")

sed -i \
	-e "s/^#define GPIO_I2C1_SDA .*/#define GPIO_I2C1_SDA ${sda_macro}/" \
	-e "s/^#define GPIO_I2C1_SCK .*/#define GPIO_I2C1_SCK ${scl_macro}/" \
	"$BOARD_H"
