#!/bin/bash
# shellcheck disable=SC2064,SC2086
# Regenerate Bootstrap Icons subset font and CSS for Thingino WebUI.
# Requires: fonttools (python3-fonttools), curl
# Usage: ./scripts/optimize-icons.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WWW_DIR="$REPO_ROOT/files/www"
VENDOR_DIR="$WWW_DIR/a/vendor"
ICONS_VER="1.13.1"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

echo "=== Finding used icons ==="
ICONS=$(cd "$WWW_DIR" && grep -rohE '\bbi-[a-z0-9-]+\b' --include='*.html' --include='*.js' . | grep -v '/vendor/' | sort -u)
COUNT=$(echo "$ICONS" | wc -l)
echo "  $COUNT icons used"

echo "=== Downloading full Bootstrap Icons $ICONS_VER ==="
curl -sL "https://cdn.jsdelivr.net/npm/bootstrap-icons@${ICONS_VER}/font/bootstrap-icons.min.css" -o "$TMPDIR/full.css"
curl -sL "https://cdn.jsdelivr.net/npm/bootstrap-icons@${ICONS_VER}/font/fonts/bootstrap-icons.woff2" -o "$TMPDIR/full.woff2"

echo "=== Extracting codepoints ==="
python3 << PYEOF
import re

with open("$TMPDIR/full.css") as f:
    css = f.read()

icons = """$ICONS""".strip().split('\n')
codepoints = set()
for icon in icons:
    if not icon:
        continue
    pattern = re.escape('.' + icon) + r'::before\{content:"\\([0-9a-fA-F]+)"\}'
    m = re.search(pattern, css)
    if m:
        codepoints.add(m.group(1))
    else:
        print(f"WARNING: {icon} not found", flush=True)

print(f"  {len(codepoints)} codepoints for {len(icons)} icons")
with open("$TMPDIR/codepoints.txt", "w") as f:
    f.write(','.join(sorted(codepoints)))
PYEOF

echo "=== Subsetting font ==="
python3 -m fontTools.subset "$TMPDIR/full.woff2" \
  --unicodes="$(cat $TMPDIR/codepoints.txt)" \
  --output-file="$VENDOR_DIR/fonts/bootstrap-icons.woff2" \
  --flavor=woff2 --no-hinting --drop-tables='' --layout-features='' 2>&1 \
  | grep -v '^$' || true
echo "  $(wc -c < "$TMPDIR/full.woff2") → $(wc -c < "$VENDOR_DIR/fonts/bootstrap-icons.woff2") bytes"

echo "=== Generating subset CSS ==="
python3 << PYEOF
import re

with open("$TMPDIR/full.css") as f:
    css = f.read()

icons = """$ICONS""".strip().split('\n')
fontface = re.search(r'@font-face\{[^}]+\}', css).group(0)
rules = []
for icon in icons:
    if not icon:
        continue
    pattern = re.escape('.' + icon) + r'::before\{[^}]+\}'
    m = re.search(pattern, css)
    if m:
        rules.append(m.group(0))

subset = f"""/*!
 * Bootstrap Icons v$ICONS_VER — subset ({len(rules)} icons used by Thingino WebUI)
 * Licensed under MIT
 */
{fontface}
{chr(10).join(rules)}
"""
with open("$VENDOR_DIR/bootstrap-icons.min.css", "w") as f:
    f.write(subset)

print(f"  CSS: {len(subset)} bytes, {len(rules)} icons")
PYEOF

echo ""
echo "=== Done ==="
du -sh "$VENDOR_DIR"
du -sh "$VENDOR_DIR"/*
