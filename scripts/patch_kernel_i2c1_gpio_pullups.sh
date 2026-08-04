#!/bin/sh

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: patch_kernel_i2c1_gpio_pullups.sh <buildroot.config> <gpio_customized.c>" >&2
	exit 1
fi

SOURCE="$1"
GPIO_C="$2"

get_value() {
	key="$1"
	[ -f "$SOURCE" ] || return 0
	sed -n "s/^${key}=//p" "$SOURCE" | head -n1
}

[ -f "$GPIO_C" ] || exit 0

[ "$(get_value BR2_PACKAGE_THINGINO_KOPT_I2C_BUS1_GPIO)" = "y" ] || exit 0
[ "$(get_value BR2_THINGINO_I2C1_GPIO_PULLUP)" = "y" ] || exit 0

sda=$(get_value BR2_THINGINO_I2C1_GPIO_SDA)
scl=$(get_value BR2_THINGINO_I2C1_GPIO_SCL)

case "$sda" in '' | *[!0-9]*) exit 0 ;; esac
case "$scl" in '' | *[!0-9]*) exit 0 ;; esac

# Only enable the pull/drive-strength initcall once we're actually going to
# populate the pull table below -- leave it untouched (commented out, as
# upstream ships it) otherwise. This also runs the pre-existing MMC
# drive-strength table, which the initcall being disabled by default upstream
# suggests was never verified safe this early in boot; don't enable it for
# boards that don't need it.
sed -i 's,^//arch_initcall(gpio_customized_init);,arch_initcall(gpio_customized_init);,' "$GPIO_C"

if grep -Fq "THINGINO_I2C1_GPIO_PULLUP" "$GPIO_C"; then
	exit 0
fi

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

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

awk -v sda="$sda_macro" -v scl="$scl_macro" '
	/static gpio_pull_table_t soc_gpio_pull_table\[\] = \{/ {
		print
		print "\t/* THINGINO_I2C1_GPIO_PULLUP */"
		print "\t{ " scl ", GPIO_PULL_UP }, //I2C1 SCL (soft-gpio, MCU bus)"
		print "\t{ " sda ", GPIO_PULL_UP }, //I2C1 SDA (soft-gpio, MCU bus)"
		next
	}
	{ print }
' "$GPIO_C" >"$tmp_file"

mv "$tmp_file" "$GPIO_C"
