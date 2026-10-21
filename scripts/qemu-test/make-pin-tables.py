#!/usr/bin/env python3
"""Pin tables for qemu-dev's pin log, from the PINOUT sheets in
ingenic-docs (text/<SoC>/HDK/<SoC> PINOUT and IP Camera GPIO
Recommended*.md): each pin's four functions, its state out of reset,
its voltage domain and its BGA ball and QFN pin, a blank one where that
package leaves the pin out.

usage: make-pin-tables.py INGENIC_DOCS_DIR [SOC ...]
"""
import csv
import glob
import io
import json
import os
import re
import sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "qemutest", "pins")
HEAD = re.compile(r"P([A-F]) group$", re.I)


def blocks(path):
    """The csv blocks of an extracted spreadsheet, by sheet name."""
    sheet, rows, inside = None, [], False
    for line in open(path, encoding="utf-8"):
        if line.startswith("## Sheet: "):
            sheet = line[10:].strip()
        elif line.startswith("```csv"):
            inside, rows = True, []
        elif line.startswith("```") and inside:
            inside = False
            yield sheet, list(csv.reader(io.StringIO("".join(rows))))
        elif inside:
            rows.append(line)


def table(path):
    pins = {}
    for sheet, rows in blocks(path):
        cols = None
        for row in rows:
            cells = [c.strip() for c in row]
            m = next((HEAD.match(c) for c in cells if HEAD.match(c)), None)
            if m:
                port, at = m.group(1).upper(), cells.index(m.group(0))
                cols = {c.lower(): i for i, c in enumerate(cells) if c}
                last = -1
                continue
            if not cols or len(cells) <= at + 2:
                continue

            def col(key):
                i = next((cols[k] for k in cols if k.startswith(key)), None)
                return cells[i] if i is not None and i < len(cells) else ""

            name = cells[at]
            if name and not re.fullmatch(rf"P{port}\d\d", name):
                cols = None
                continue
            func = [col(f"func{i}") for i in range(4)]
            # unnamed rows: the analog pads at a port's start, in order
            if not name and not any(func):
                continue
            n = int(name[2:]) if name else last + 1
            if n > 31:
                cols = None
                continue
            last = n
            pins[f"P{port}{n}"] = {
                "func": func,
                "reset": col("default status"),
                "power": col("power voltage"),
                "bga": col("pin number in bga"),
                "qfn": col("pin number in qfn"),
            }
    return pins


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    docs = os.path.join(sys.argv[1], "text")
    socs = [s.upper() for s in sys.argv[2:]] or sorted(os.listdir(docs))
    os.makedirs(OUT, exist_ok=True)
    for soc in socs:
        found = sorted(glob.glob(os.path.join(
            docs, soc, "HDK", f"{soc} PINOUT*.md")))
        found = [f for f in found if not f.endswith(".min.md")]
        english = [f for f in found if "_EN" in f] or found
        for path in english:
            pins = table(path)
            if pins:
                break
        else:
            continue
        src = os.path.basename(path)[:-3]
        with open(os.path.join(OUT, f"{soc.lower()}.json"), "w") as f:
            json.dump({"soc": soc.lower(), "source": src, "pins": pins}, f,
                      indent=1, ensure_ascii=False)
            f.write("\n")
        print(f"{soc.lower()}: {len(pins)} pins from {src}")


if __name__ == "__main__":
    main()
