#!/bin/sh
# Print a button gpio number from a camera's device-tree fragment, or nothing
# when the fragment defines no such button.
#
# The fragment is the single source for the reset/chime pins: the 4.4+ kernel
# takes them from the device tree gpio-keys node, and both the U-Boot injection
# and S09mmc's 3.10 gpio-userkeys take them from here.
#
# Usage: button_pins.sh <camera.dtsi> <reset|chime>

set -eu

DTSI="${1:-}"
KEY="${2:-reset}"
[ -n "$DTSI" ] && [ -f "$DTSI" ] || exit 0

python3 - "$DTSI" "$KEY" <<'PY'
import re
import sys

src = open(sys.argv[1]).read()
key = sys.argv[2]

m = re.search(r'^[ \t]*gpio-keys[ \t]*\{', src, re.M)
if not m:
    sys.exit(0)
depth, start = 0, src.index("{", m.start())
block = ""
for i in range(start, len(src)):
    if src[i] == "{":
        depth += 1
    elif src[i] == "}":
        depth -= 1
        if depth == 0:
            block = src[start + 1:i]
            break

base = {"a": 0, "b": 32, "c": 64, "d": 96, "e": 128}
for child in re.finditer(r'([A-Za-z0-9_\-]+)[ \t]*\{([^{}]*)\}', block):
    body = child.group(2)
    label = re.search(r'label[ \t]*=[ \t]*"([^"]+)"', body)
    name = label.group(1) if label else child.group(1)
    if name != key:
        continue
    gpio = re.search(r'(?:^|[ \t])gpios[ \t]*=[ \t]*<[ \t]*&gp([a-e])[ \t]+(\d+)', body, re.M)
    if gpio:
        print(base[gpio.group(1)] + int(gpio.group(2)))
    break
PY
