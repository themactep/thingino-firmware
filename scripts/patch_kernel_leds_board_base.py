#!/usr/bin/env python3

import sys
from pathlib import Path


DEVICE_BLOCK = """
#if defined(CONFIG_LEDS_GPIO) && (THINGINO_GPIO_LEDS_COUNT > 0)
static struct gpio_led thingino_gpio_leds[] __initdata = {
	THINGINO_GPIO_LEDS_ITEMS
};

static struct gpio_led_platform_data thingino_gpio_led_pdata __initdata = {
	.num_leds = ARRAY_SIZE(thingino_gpio_leds),
	.leds = thingino_gpio_leds,
};

static struct platform_device thingino_gpio_led_device = {
	.name = "leds-gpio",
	.id = -1,
};
#endif

"""

ARRAY_BLOCK = """
#if defined(CONFIG_LEDS_GPIO) && (THINGINO_GPIO_LEDS_COUNT > 0)
	DEF_DEVICE(&thingino_gpio_led_device, &thingino_gpio_led_pdata,
		   sizeof(struct gpio_led_platform_data)),
#endif
"""


def patch_board_base(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    if "thingino_gpio_led_device" in text:
        return

    include_gpio = "#include <mach/jzmmc.h>\n#include <gpio.h>"
    include_board = '#include "board_base.h"\n#include <mach/jzssi.h>'
    struct_anchor = "struct jz_platform_device\n"
    array_anchor = "#ifdef CONFIG_KEYBOARD_GPIO\n\tDEF_DEVICE(&jz_button_device, 0, 0),\n#endif\n"

    if include_gpio not in text or include_board not in text or struct_anchor not in text or array_anchor not in text:
        raise SystemExit(f"unsupported board_base layout: {path}")

    text = text.replace(include_gpio, "#include <mach/jzmmc.h>\n#include <linux/leds.h>\n#include <gpio.h>", 1)
    text = text.replace(include_board, '#include "board_base.h"\n#include "thingino_leds.h"\n#include <mach/jzssi.h>', 1)
    text = text.replace(struct_anchor, DEVICE_BLOCK + struct_anchor, 1)
    text = text.replace(array_anchor, array_anchor + ARRAY_BLOCK, 1)

    path.write_text(text, encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: patch_kernel_leds_board_base.py <board_base.c>", file=sys.stderr)
        return 1

    board_base = Path(sys.argv[1])
    if not board_base.is_file():
        return 0

    patch_board_base(board_base)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())