#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
	echo "usage: patch_kernel_leds_board_base.sh <board_base.c>" >&2
	exit 1
fi

BOARD_BASE="$1"

if [ ! -f "$BOARD_BASE" ]; then
	exit 0
fi

if grep -Fq "thingino_gpio_led_device" "$BOARD_BASE"; then
	exit 0
fi

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

if ! perl -0777 -e '
use strict;
use warnings;

my $text = do { local $/; <STDIN> };

my $include_gpio = "#include <mach/jzmmc.h>\n#include <gpio.h>";
my $include_board = "#include \"board_base.h\"\n#include <mach/jzssi.h>";
my $struct_anchor = "struct jz_platform_device\n";
my $array_anchor_re = qr/#ifdef CONFIG_KEYBOARD_GPIO\n[ \t]*DEF_DEVICE\(&jz_button_device, 0, 0\),\n#endif/;

die "unsupported\n"
	if index($text, $include_gpio) < 0
	|| index($text, $include_board) < 0
	|| index($text, $struct_anchor) < 0
	|| $text !~ $array_anchor_re;

my $device_block = "\n"
	. "#if defined(CONFIG_LEDS_GPIO) && (THINGINO_GPIO_LEDS_COUNT > 0)\n"
	. "static struct gpio_led thingino_gpio_leds[] __initdata = {\n"
	. "\tTHINGINO_GPIO_LEDS_ITEMS\n"
	. "};\n\n"
	. "static struct gpio_led_platform_data thingino_gpio_led_pdata __initdata = {\n"
	. "\t.num_leds = ARRAY_SIZE(thingino_gpio_leds),\n"
	. "\t.leds = thingino_gpio_leds,\n"
	. "};\n\n"
	. "static struct platform_device thingino_gpio_led_device = {\n"
	. "\t.name = \"leds-gpio\",\n"
	. "\t.id = -1,\n"
	. "};\n"
	. "#endif\n\n";

my $array_block = "\n#if defined(CONFIG_LEDS_GPIO) && (THINGINO_GPIO_LEDS_COUNT > 0)\n"
	. "\tDEF_DEVICE(&thingino_gpio_led_device, &thingino_gpio_led_pdata,\n"
	. "\t\t   sizeof(struct gpio_led_platform_data)),\n"
	. "#endif\n";

$text =~ s/\Q$include_gpio\E/#include <mach\/jzmmc.h>\n#include <linux\/leds.h>\n#include <gpio.h>/;
$text =~ s/\Q$include_board\E/#include "board_base.h"\n#include "thingino_leds.h"\n#include <mach\/jzssi.h>/;
$text =~ s/\Q$struct_anchor\E/$device_block$struct_anchor/;
$text =~ s/($array_anchor_re)/$1$array_block/;

print $text;
' <"$BOARD_BASE" >"$tmp_file"; then
	echo "unsupported board_base layout: $BOARD_BASE" >&2
	exit 1
fi

mv "$tmp_file" "$BOARD_BASE"
