#!/usr/bin/env python3
"""Generate motors.json files for camera configs."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Iterable

ROOT = Path(__file__).resolve().parents[1]
CAMERAS_DIR = ROOT / "configs" / "cameras"
CONFIG_KEYS: tuple[str, ...] = (
    "motors_homing",
    "motor_maxstep_h",
    "motor_maxstep_v",
    "motor_speed_h",
    "motor_speed_v",
)
UENV_KEYS: tuple[str, ...] = (
    "gpio_motor_h",
    "gpio_motor_v",
    "gpio_motor_switch",
)
TRUE_VALUES = {"1", "true", "yes", "on"}
SPI_GPIOLESS_CAMERAS = {
    "eufy_t8400x_t31x_sc3235_syn4343",
    "eufy_t8400x_t31x_sc3335_syn4343",
    "eufy_t8400x_t31x_sc3338_syn4343",
}


def parse_simple_kv(path: Path, keys: Iterable[str]) -> dict[str, str]:
    data: dict[str, str] = {}
    if not path.exists():
        return data
    with path.open(encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            key = key.strip()
            if key not in keys:
                continue
            data[key] = value.strip().strip('"')
    return data


def as_bool(value: str) -> bool:
    return value.strip().lower() in TRUE_VALUES


def as_int(value: str) -> int:
    return int(value.strip(), 10)


def main() -> None:
    written = 0
    skipped: list[tuple[str, str]] = []

    for config_path in sorted(CAMERAS_DIR.rglob("*.config")):
        camera_dir = config_path.parent
        camera_name = camera_dir.name
        uenv_path = camera_dir / f"{camera_name}.uenv.txt"

        cfg_values = parse_simple_kv(config_path, CONFIG_KEYS)
        gpio_values = parse_simple_kv(uenv_path, UENV_KEYS)

        if not all(key in cfg_values for key in CONFIG_KEYS):
            skipped.append((camera_name, "missing motor config keys"))
            continue
        is_spi = camera_name in SPI_GPIOLESS_CAMERAS

        has_gpio_pan = "gpio_motor_h" in gpio_values
        has_gpio_tilt = "gpio_motor_v" in gpio_values

        if not is_spi and not (has_gpio_pan or has_gpio_tilt):
            skipped.append((camera_name, "missing motor gpio pan/tilt pins"))
            continue

        steps_pan = as_int(cfg_values["motor_maxstep_h"])
        steps_tilt = as_int(cfg_values["motor_maxstep_v"])
        speed_pan = as_int(cfg_values["motor_speed_h"])
        speed_tilt = as_int(cfg_values["motor_speed_v"])
        pos_0 = f"{steps_pan // 2},{steps_tilt // 2}"
        switch_value = (
            as_int(gpio_values["gpio_motor_switch"])
            if "gpio_motor_switch" in gpio_values
            else -1
        )
        gpio_pan = "" if is_spi or not has_gpio_pan else gpio_values["gpio_motor_h"]
        gpio_tilt = "" if is_spi or not has_gpio_tilt else gpio_values["gpio_motor_v"]

        motors_payload = {
            "gpio_invert": False,
            "gpio_pan": gpio_pan,
            "gpio_switch": switch_value,
            "gpio_tilt": gpio_tilt,
            "homing": as_bool(cfg_values["motors_homing"]),
            "pos_0": pos_0,
            "speed_pan": speed_pan,
            "speed_tilt": speed_tilt,
            "steps_pan": steps_pan,
            "steps_tilt": steps_tilt,
        }

        out_path = camera_dir / "motors.json"
        content = json.dumps({"motors": motors_payload}, indent=2, ensure_ascii=True)
        content += "\n"

        if out_path.exists() and out_path.read_text(encoding="utf-8") == content:
            continue

        out_path.write_text(content, encoding="utf-8")
        written += 1

    print(f"Generated or updated {written} motors.json files.")
    if skipped:
        print("Skipped entries:")
        for name, reason in skipped:
            print(f"  - {name}: {reason}")


if __name__ == "__main__":
    main()
