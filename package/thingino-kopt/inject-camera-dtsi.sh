#!/bin/sh
# Inject a camera's static GPIO fragment into the leaf .dts the kernel config
# builds, 4.4 and later only. The fragment (a single .dtsi in the camera
# profile dir) carries board pins that the kernel consumes from the device
# tree: gpio-leds and the MMC card-detect override. It is copied into the
# tree's dts dir and #included by the leaf.
#
# A tree with no device-tree directory (every 3.10 kernel) is left untouched,
# so the fragment is inert there. A leaf whose include chain does not define
# every label the fragment opens (&gpa..&gpd, &msc0) is skipped, and so is a
# leaf that already declares a gpio-leds node - that keeps a fragment shipped
# ahead of a family's 4.4 tree from breaking that family's build.
#
# When the fragment declares a gpio-keys node, the SoC tree's own dev-board
# gpio_keys node (power/boot select) is deleted first - by label when present
# (the Ingenic trees carry "gpio_keys: gpio_keys"), else by node name - or
# gpio-keys would claim those pins on every board.
#
# Usage: inject-camera-dtsi.sh <camera.dtsi> <linux-dir>
set -e

SRC="$1"
LINUX="$2"
[ -f "$SRC" ] || exit 0
[ -n "$LINUX" ] || exit 0

DTSDIR="$LINUX/arch/mips/boot/dts/ingenic"
[ -f "$DTSDIR/Makefile" ] && [ -f "$LINUX/.config" ] || exit 0

python3 - "$SRC" "$LINUX" "$DTSDIR" <<'PY'
import os, re, shutil, sys

src, linux, dtsdir = sys.argv[1], sys.argv[2], sys.argv[3]
name = os.path.basename(src)
frag = open(src).read()

# Labels the fragment opens with "&label" that the leaf chain must define.
wanted = sorted(set(re.findall(r'&([A-Za-z_][A-Za-z0-9_]*)', frag)))
adds_leds = bool(re.search(r'^[ \t]*gpio-leds[ \t]*\{', frag, re.M))
adds_keys = bool(re.search(r'^[ \t]*gpio-keys[ \t]*\{', frag, re.M))

LEDS_RE = re.compile(r'^[ \t]*gpio-leds[ \t]*\{', re.M)
KEY_LABEL_RE = re.compile(r'^[ \t]*gpio_keys[ \t]*:', re.M)
KEY_NODE_RE = re.compile(r'^[ \t]*(gpio[-_]keys)[ \t]*\{', re.M)
LABEL_RE = re.compile(r'(?:^|[:{\s])([A-Za-z_][A-Za-z0-9_]*)[ \t]*:', re.M)
INCLUDE_RE = re.compile(r'^[ \t]*#include[ \t]+"([^"]+)"', re.M)


def load(path, seen):
    if path in seen or not os.path.isfile(path):
        return ""
    seen.add(path)
    s = open(path).read()
    for inc in INCLUDE_RE.findall(s):
        s += "\n" + load(os.path.join(os.path.dirname(path), inc), seen)
    return s


# The trees this kernel config builds, from the dtb-$(CONFIG_...) lines.
built = []
for line in open(os.path.join(dtsdir, "Makefile")):
    m = re.match(r'^dtb-\$\((\w+)\)\s*\+=\s*(\S+)\.dtb', line)
    if m:
        built.append((m.group(1), m.group(2)))

cfg = open(os.path.join(linux, ".config")).read()
shutil.copyfile(src, os.path.join(dtsdir, name))

applied, skipped = [], []
for opt, leaf in built:
    if not re.search(r'^%s=y' % re.escape(opt), cfg, re.M):
        continue
    path = os.path.join(dtsdir, leaf + ".dts")
    if not os.path.isfile(path):
        continue
    body = open(path).read()
    if re.search(r'#include[ \t]+"%s"' % re.escape(name), body):
        applied.append(leaf)          # already injected on an earlier build
        continue
    chain = load(path, set())
    labels = set(m.group(1) for m in LABEL_RE.finditer(chain))
    missing = [l for l in wanted if l not in labels]
    if missing:
        skipped.append("%s (no label: %s)" % (leaf, ", ".join(missing)))
        continue
    if adds_leds and LEDS_RE.search(chain):
        skipped.append("%s (gpio-leds already present)" % leaf)
        continue
    deletes = []
    if adds_keys:
        if KEY_LABEL_RE.search(chain):
            deletes.append("/delete-node/ &gpio_keys;")
        else:
            for nm in KEY_NODE_RE.finditer(body):
                deletes.append("/delete-node/ %s;" % nm.group(1))
    with open(path, "a") as f:
        for d in deletes:
            f.write("\n%s\n" % d)
        f.write('\n#include "%s"\n' % name)
    applied.append(leaf)

if applied:
    print("thingino: %s: included by %s" % (name, ", ".join(applied)))
for what in skipped:
    print("thingino: %s: skipped %s" % (name, what), file=sys.stderr)
if not applied:
    print("thingino: %s: no matching leaf" % name, file=sys.stderr)
PY
