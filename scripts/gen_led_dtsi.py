#!/usr/bin/env python3
"""Generate per-camera LED DTSI stubs from thingino.json GPIO LED keys."""

from __future__ import annotations

import glob
import json
import os
import re
from dataclasses import dataclass
from typing import Any


ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CAMERA_GLOB = os.path.join(ROOT, "configs", "cameras*", "*", "thingino.json")
KERNEL_DTS_MAP = os.path.join(ROOT, "configs", "camera-kernel-dts.map")


@dataclass
class LedEntry:
    name: str
    pin: int
    active_low: int
    active_on_boot: int


def _bank_letter(pin: int) -> str | None:
    bank = pin // 32
    if bank < 0 or bank > 4:
        return None
    return chr(ord("a") + bank)


def _pin_offset(pin: int) -> int:
    return pin % 32


def _bool_flag(value: Any, default: int = 0) -> int:
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (int, float)):
        return 1 if int(value) != 0 else 0
    if isinstance(value, str):
        value = value.strip().strip('"').lower()
        if value in {"1", "true", "on", "yes"}:
            return 1
        if value in {"0", "false", "off", "no"}:
            return 0
    return default


def _parse_scalar_pin(raw: Any, default_active: int) -> tuple[int | None, int]:
    token = str(raw).strip().strip('"').split()
    if not token:
        return None, default_active
    token0 = token[0]
    if token0 == "-1":
        return None, default_active
    if not re.fullmatch(r"[0-9]+[oO]?", token0):
        return None, default_active

    if token0.endswith(("o", "O")):
        pin_str = token0[:-1]
        if not pin_str:
            return None, default_active
        active = 1 if token0.endswith("o") else 0
    else:
        pin_str = token0
        active = default_active

    try:
        pin = int(pin_str)
    except ValueError:
        return None, default_active

    if pin < 0:
        return None, default_active
    return pin, active


def _extract_led(name: str, data: Any) -> LedEntry | None:
    active_low = 0
    active_on_boot = 0
    pin: int | None = None

    if isinstance(data, dict):
        active_low = _bool_flag(data.get("active_low"), 0)
        active_on_boot = _bool_flag(data.get("active_on_boot"), 0)
        pin_value = data.get("pin")
        if isinstance(pin_value, dict):
            active_low = _bool_flag(pin_value.get("active_low"), active_low)
            active_on_boot = _bool_flag(pin_value.get("active_on_boot"), active_on_boot)
            pin, active_low = _parse_scalar_pin(pin_value.get("pin"), active_low)
        elif pin_value is not None:
            pin, active_low = _parse_scalar_pin(pin_value, active_low)
    else:
        pin, active_low = _parse_scalar_pin(data, active_low)

    if pin is None:
        return None

    return LedEntry(
        name=name,
        pin=pin,
        active_low=active_low,
        active_on_boot=active_on_boot,
    )


def _load_leds(json_path: str) -> list[LedEntry]:
    with open(json_path, "r", encoding="utf-8") as fh:
        raw = fh.read()

    # Camera configs may contain comments and trailing commas.
    raw = re.sub(r"//.*$", "", raw, flags=re.MULTILINE)
    raw = re.sub(r",(\s*[}\]])", r"\1", raw)
    payload = json.loads(raw)
    gpio = payload.get("gpio", {}) if isinstance(payload, dict) else {}
    if not isinstance(gpio, dict):
        return []

    out: list[LedEntry] = []
    for key, value in sorted(gpio.items()):
        if not key.startswith("led_"):
            continue
        led = _extract_led(key, value)
        if led is not None:
            out.append(led)
    return out


def _render(camera: str, leds: list[LedEntry]) -> str:
    lines = [
        f"/* generated from configs for {camera} */",
        "/ {",
        "\tleds {",
        '\t\tcompatible = "gpio-leds";',
    ]

    if not leds:
        lines.append('\t\tstatus = "disabled";')
    else:
        for led in leds:
            bank = _bank_letter(led.pin)
            if bank is None:
                continue
            offset = _pin_offset(led.pin)
            default_state = "on" if led.active_on_boot else "off"
            lines.extend(
                [
                    f"\t\t{led.name} {{",
                    f'\t\t\tlabel = "thingino:{led.name}";',
                    f"\t\t\tgpios = <&{{/soc/pinctrl@0x10010000/gp{bank}}} {offset} {led.active_low} 0>;",
                    f'\t\t\tdefault-state = "{default_state}";',
                    "\t\t};",
                ]
            )

    lines.extend(["\t};", "};", ""])
    return "\n".join(lines)


def _read_kernel_dts_map(path: str) -> dict[str, str]:
    out: dict[str, str] = {}
    if not os.path.exists(path):
        return out
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            camera, dts_name = line.split("=", 1)
            camera = camera.strip()
            dts_name = dts_name.split("#", 1)[0].strip()
            if camera and dts_name:
                out[camera] = dts_name
    return out


def _render_overlay_dts(camera: str, base_dts: str) -> str:
    base = base_dts if base_dts.endswith(".dts") else f"{base_dts}.dts"
    return "\n".join(
        [
            "/dts-v1/;",
            f"/* generated overlay wrapper for {camera} */",
            f'/include/ "{base}"',
            '/include/ "leds.dtsi"',
            "",
        ]
    )


def main() -> int:
    dts_map = _read_kernel_dts_map(KERNEL_DTS_MAP)
    generated = 0
    for json_path in sorted(glob.glob(CAMERA_GLOB)):
        camera_dir = os.path.dirname(json_path)
        camera = os.path.basename(camera_dir)
        leds = _load_leds(json_path)

        out_path = os.path.join(camera_dir, "leds.dtsi")
        content = _render(camera, leds)
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(content)

        base_dts = dts_map.get(camera, camera)
        overlay_path = os.path.join(camera_dir, "leds-overlay.dts")
        overlay_content = _render_overlay_dts(camera, base_dts)
        with open(overlay_path, "w", encoding="utf-8") as fh:
            fh.write(overlay_content)

        generated += 1

    print(f"generated {generated} camera led dtsi files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
