#!/usr/bin/env python3
"""Tiny template renderer for Thingino build steps.

Supported syntax inside the template file:
  @VAR@                -> simple placeholder substitution
  @if VAR@             -> include following block when VAR is truthy (non-empty, not 0/false)
  @else@               -> optional else block paired with @if
  @endif@              -> terminates the most recent @if

Example:
  @if WIFI_IS_SDIO@
  echo "SDIO"
  @else@
  echo "USB"
  @endif@

Usage:
  render_template.py --template input --output output --var FOO=bar --var FLAG=1
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Render Thingino template files")
    parser.add_argument("--template", required=True, help="Path to the template file")
    parser.add_argument("--output", required=True, help="Path to write the rendered file")
    parser.add_argument(
        "--var",
        action="append",
        default=[],
        help="Key=value pair to inject into the template"
    )
    return parser.parse_args()


def parse_vars(raw: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for item in raw:
        if "=" not in item:
            raise SystemExit(f"Invalid --var '{item}', expected KEY=VALUE")
        key, value = item.split("=", 1)
        key = key.strip()
        if not key:
            raise SystemExit(f"Invalid --var '{item}', empty key")
        result[key] = value
    return result


def is_truthy(value: str) -> bool:
    return value not in ("", "0", "false", "False", "no", "No")


def render(template: Path, output: Path, variables: dict[str, str]) -> None:
    stack: list[tuple[bool, bool]] = []  # (parent_active, current_active)
    active = True
    out_lines: list[str] = []

    lines = template.read_text(encoding="utf-8").splitlines(keepends=True)
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("@if "):
            condition = stripped[4:].strip()
            invert = False
            if condition.endswith("@"):
                condition = condition[:-1].strip()
            if condition.startswith("!"):
                invert = True
                condition = condition[1:].strip()
                if condition.endswith("@"):
                    condition = condition[:-1].strip()
            cond_value = variables.get(condition, "")
            cond_result = is_truthy(cond_value)
            if invert:
                cond_result = not cond_result
            stack.append((active, active and cond_result))
            active = stack[-1][1]
            continue
        if stripped == "@else@":
            if not stack:
                raise SystemExit("@else@ without matching @if")
            parent_active, current_active = stack[-1]
            active = parent_active and not current_active
            stack[-1] = (parent_active, active)
            continue
        if stripped == "@endif@":
            if not stack:
                raise SystemExit("@endif@ without matching @if")
            active = stack.pop()[0]
            continue
        if not active:
            continue
        rendered = line
        for key, value in variables.items():
            rendered = rendered.replace(f"@{key}@", value)
        out_lines.append(rendered)

    if stack:
        raise SystemExit("Unclosed @if block in template")

    output.write_text("".join(out_lines), encoding="utf-8")


def main() -> None:
    args = parse_args()
    vars_dict = parse_vars(args.var)
    render(Path(args.template), Path(args.output), vars_dict)


if __name__ == "__main__":
    main()
