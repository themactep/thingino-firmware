#!/usr/bin/env python3
"""Sort thingino camera defconfig entries alphabetically.

Layout rules (see also the "sort-defconfigs" skill):

  * Header: only the leading '# NAME:' and '# FRAG:' comment lines
    are left untouched. Any other leading comments are treated as part
    of the body.
  * Footer: the trailing run of blank lines and freeform comments
    (notes that are not commented-out config entries) is left untouched,
    except that trailing blank lines are stripped.
  * Body: everything in between is sorted in stable C-locale (byte)
    order. The sort key is the full line with any leading '#' and
    whitespace stripped:
      - '=' (0x3D) sorts before '_' (0x5F), so
        BR2_PACKAGE_THINGINO_KOPT_DWC2=y comes before
        BR2_PACKAGE_THINGINO_KOPT_DWC2_OTG=y;
      - commented-out entries (#BR2_...=..., # FLASH_...=...) sort by
        their option name, next to their active siblings;
      - freeform annotation comments are glued to the entry that
        follows them and move with it;
      - blank lines inside the body are dropped;
      - duplicate keys keep their relative order (stable sort).

Usage:
  scripts/sort_defconfig.py [--check] [FILE ...]

Without FILE arguments, all defconfigs under configs/cameras*/ are
processed. With --check no files are modified and exit code 1 signals
files that are not sorted.
"""

import glob
import re
import sys

COMMENTED_ENTRY = re.compile(r"^#\s*(BR2_|FLASH_)[A-Za-z0-9_]*=")
HEADER_LINE = re.compile(r"^\s*#\s*(NAME|FRAG):")


def sort_defconfig(text):
    lines = text.splitlines()
    n = len(lines)

    # header: leading '# NAME:' / '# FRAG:' lines only
    i = 0
    while i < n and HEADER_LINE.match(lines[i]):
        i += 1

    # footer: trailing run of blank lines and freeform comments
    j = n
    while j > i:
        s = lines[j - 1].strip()
        if s == "" or (s.startswith("#") and not COMMENTED_ENTRY.match(s)):
            j -= 1
        else:
            break

    # body: attach freeform comments to the entry that follows them
    groups = []
    pending = []
    for line in lines[i:j]:
        s = line.strip()
        if s == "":
            continue
        if s.startswith("#") and not COMMENTED_ENTRY.match(s):
            pending.append(line)
            continue
        groups.append((pending, line))
        pending = []

    groups.sort(key=lambda g: g[1].lstrip("#").lstrip())  # stable

    out = lines[:i]
    for comments, entry in groups:
        out.extend(comments)
        out.append(entry)
    out.extend(pending)  # dangling comments, keep before footer
    out.extend(lines[j:])
    while out and out[-1].strip() == "":
        out.pop()
    return "\n".join(out) + "\n"


def main(argv):
    check = False
    files = []
    for arg in argv:
        if arg == "--check":
            check = True
        elif arg == "--":
            continue
        else:
            files.append(arg)

    if not files:
        files = sorted(
            glob.glob("configs/cameras/*/*defconfig*")
            + glob.glob("configs/cameras-exp/*/*defconfig*")
        )

    dirty = []
    for path in files:
        with open(path) as f:
            text = f.read()
        new = sort_defconfig(text)
        if new == text:
            continue
        dirty.append(path)
        if check:
            print(f"not sorted: {path}")
        else:
            with open(path, "w") as f:
                f.write(new)
            print(f"sorted: {path}")

    return 1 if (check and dirty) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
