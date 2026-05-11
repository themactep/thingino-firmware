#!/usr/bin/env python3

import json
import sys
from pathlib import Path


LED_COLOR_MAP = {
    "B": "led_b",
    "G": "led_g",
    "R": "led_r",
    "V": "led_v",
    "W": "led_w",
    "Y": "led_y",
}


def parse_bool(value, default=False):
    if isinstance(value, bool):
        return value
    if isinstance(value, int):
        return value != 0
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "on", "yes"}:
            return True
        if normalized in {"0", "false", "off", "no"}:
            return False
    return default


def parse_pin_scalar(value, active_low_default):
    if isinstance(value, int):
        return (value, active_low_default)
    if not isinstance(value, str):
        return None

    token = value.strip().split()[0] if value.strip() else ""
    if not token:
        return None

    active_low = active_low_default
    if token.endswith("o"):
        token = token[:-1]
        active_low = True
    elif token.endswith("O"):
        token = token[:-1]
        active_low = False

    if not token or not token.isdigit():
        return None

    return (int(token), active_low)


def extract_led_definition(name, value):
    active_low = False
    active_on_boot = False

    if isinstance(value, dict):
        active_low = parse_bool(value.get("active_low"), active_low)
        active_on_boot = parse_bool(value.get("active_on_boot"), active_on_boot)

        pin_value = value.get("pin", value)
        if isinstance(pin_value, dict):
            active_low = parse_bool(pin_value.get("active_low"), active_low)
            active_on_boot = parse_bool(pin_value.get("active_on_boot"), active_on_boot)
            pin_value = pin_value.get("pin")
    else:
        pin_value = value

    parsed = parse_pin_scalar(pin_value, active_low)
    if not parsed:
        return None

    pin, active_low = parsed
    if pin < 0:
        return None

    return {
        "name": name,
        "pin": pin,
        "active_low": active_low,
        "active_on_boot": active_on_boot,
    }


def build_leds(config):
    gpio = config.get("gpio", {})
    leds = []
    for name in sorted(gpio):
        if not name.startswith("led_"):
            continue
        led = extract_led_definition(name, gpio[name])
        if led:
            leds.append(led)
    return leds


def parse_buildroot_config(path):
    values = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value.strip().strip('"')
    return values


def build_leds_from_buildroot_config(path):
    values = parse_buildroot_config(path)
    leds = []
    for color, led_name in LED_COLOR_MAP.items():
        gpio_key = f"BR2_THINGINO_LED_{color}_GPIO"
        gpio_value = values.get(gpio_key, "-1")
        if not gpio_value.lstrip("-").isdigit():
            continue
        gpio = int(gpio_value)
        if gpio < 0:
            continue
        leds.append(
            {
                "name": led_name,
                "pin": gpio,
                "active_low": values.get(f"BR2_THINGINO_LED_{color}_ACTIVE_LOW") == "y",
                "active_on_boot": values.get(f"BR2_THINGINO_LED_{color}_ACTIVE_ON_BOOT") == "y",
            }
        )
    return leds


def render_header(leds):
    lines = [
        "#ifndef __THINGINO_GENERATED_LEDS_H__",
        "#define __THINGINO_GENERATED_LEDS_H__",
        "",
        "#define THINGINO_GPIO_LEDS_COUNT %d" % len(leds),
        "",
        "#define THINGINO_GPIO_LEDS_ITEMS \\",
    ]

    if leds:
        for index, led in enumerate(leds):
            default_state = "LEDS_GPIO_DEFSTATE_ON" if led["active_on_boot"] else "LEDS_GPIO_DEFSTATE_OFF"
            suffix = " " + chr(92) if index != len(leds) - 1 else ""
            lines.append(
                '\t{ .name = "%s", .gpio = %d, .active_low = %d, .default_state = %s },%s'
                % (led["name"], led["pin"], 1 if led["active_low"] else 0, default_state, suffix)
            )
    else:
        lines.append("\t/* no generated LEDs */")

    lines.extend([
        "",
        "#endif",
        "",
    ])
    return "\n".join(lines)


def main():
    if len(sys.argv) != 3:
        print("usage: generate_kernel_led_header.py <thingino.json> <output.h>", file=sys.stderr)
        return 1

    source = Path(sys.argv[1])
    target = Path(sys.argv[2])

    if not source.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(render_header([]), encoding="ascii")
        return 0

    if source.suffix == ".json":
        with source.open("r", encoding="utf-8") as handle:
            config = json.load(handle)
        leds = build_leds(config)
    else:
        leds = build_leds_from_buildroot_config(source)

    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(render_header(leds), encoding="ascii")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())