#!/usr/bin/env python3
"""Pin tables for qemu-dev's pin log, from ingenic-docs: each pin's four
functions, its state out of reset, its voltage domain and its BGA ball and
QFN pin, a blank one where that package leaves the pin out.

A SoC's HDK pinout or GPIO allocation sheet comes first, else the pin
chapter of its datasheet. The T10, T21 and T30 datasheets list a pin's
functions in order but skip the empty ones: a function's number is
certain where the vendor kernel selects it or the order leaves it only
one, else it follows the T31 and T23 sheets for the same pin and name, or
takes the first free number, and the name gets a trailing "?".

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

# the ingenic-docs folder and sources, best first: a later source only
# fills what the ones before it left blank; the newest English file wins
SOURCES = {
    "a1": ("A1", ["HDK/GPIO recommended allocation table of A1_*"]),
    "c100": ("C100", ["HDK/C100_ IP Camera Solution GPIO Recommended*"]),
    "cw080": ("CW080", ["Datasheets/CW080SN_ds_*"]),
    "t10": ("T10", ["Datasheets/T10_DS_*"]),
    # the T10 die with other clocks, in the same TFBGA181 package
    "t20": ("T10", ["Datasheets/T10_DS_*"]),
    "t21": ("T21", ["Datasheets/T21_DS_20180807"]),
    "t23": ("T23", ["HDK/T23 PINOUT*_EN_*"]),
    "t30": ("T30", ["Datasheets/T30 Smart Video*"]),
    "t31": ("T31", ["HDK/T31 PINOUT*_EN_20190823"]),
    "t32": ("T32", ["HDK/T32_IP Camera Solution（Normal IPC）*"]),
    "t32pro": ("T32Pro", ["Datasheets/T32ProVX_ds_*"]),
    "t33": ("T33", ["HDK/T33_IP Camera Solution（Normal IPC）*"]),
    "t40": ("T40", ["HDK/T40_IP Camera Solution GPIO*",
                    "HDK/T40 PIN information description_*"]),
    "t41": ("T41", ["HDK/T41_IP Camera Solution GPIO Recommended*"]),
}
# the sheets an older datasheet's function numbers are matched against
REFERENCE = ["t31", "t23"]

HEAD = re.compile(r"P([A-F]) ?gr(?:ou|uo)p$", re.I)  # T40's say "Gruop"
PIN = re.compile(r"P([A-F])(\d\d?)")
GPIO = re.compile(r"P([A-F])(\d\d)$")
FIELDS = {"reset": ("default stat", "level state"),
          "power": ("power", "voltage domain"),
          "bga": ("bga", "ball"), "qfn": ("qfn",)}


def clean(v):
    v = " ".join(v.split())
    if re.fullmatch(r"(?i)n\.?a\.?|[-/−—]", v):
        return ""
    return "analog" if re.match(r"(?i)note\s*[:：]\s*analog", v) else v


def entry(func=None, **f):
    p = {"func": func or [""] * 4}
    p.update({k: f.get(k, "") for k in FIELDS})
    return p


def merge(into, more):
    for pin, p in more.items():
        q = into.setdefault(pin, entry())
        q["func"] = [a or b for a, b in zip(q["func"], p["func"])]
        for k in FIELDS:
            q[k] = q[k] or p[k]


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


def analog(pins, rows, named):
    """Rows without a pin name: the analog pads that start a port, numbered
    by their DVP_Dn function. T32's DVP pads are no GPIOs (DVP_D10 would be
    its SADC pin PA10), so a clash drops the lot; so do pads without one."""
    found = {}
    for port, p in rows:
        m = next((re.fullmatch(r"DVP_D(\d+)", f) for f in p["func"]
                  if re.fullmatch(r"DVP_D(\d+)", f)), None)
        if not m:
            return
        found[f"P{port}{int(m.group(1))}"] = p
    if any(pin in named for pin in found):
        return
    pins.update(found)


def sheet_pins(path):
    pins = {}
    for _, rows in blocks(path):
        cols, unnamed, named = None, [], set()
        for row in rows:
            cells = [c.strip() for c in row]
            low = [c.lower() for c in cells]
            head = next((c for c in cells if HEAD.match(c)), None)
            if head or ("pin name" in low and "ball" in low):
                analog(pins, unnamed, named)
                unnamed, named = [], set()
                new = {c: i for i, c in enumerate(low) if c}
                # T41's later ports leave the package columns unlabelled
                cols = {**cols, **new} if cols and head else new
                at = cells.index(head) if head else low.index("pin name")
                port = HEAD.match(head).group(1).upper() if head else None
                continue
            if not cols or len(cells) <= at:
                continue

            def col(*keys):
                i = next((i for k, i in cols.items()
                          if any(x in k for x in keys)), None)
                return clean(cells[i]) if i is not None and i < len(cells) \
                    else ""

            name = cells[at]
            if any(re.search(r"(?i)no[nt]\s*gpio|非gpio", c) for c in cells):
                continue
            if not port:
                # a ball sheet: the pin name ends in the GPIO, as PC31
                m = re.search(r"(?:^|_)(P[A-F]\d\d)$", name)
                if m:
                    p = entry(**{k: col(*v) for k, v in FIELDS.items()})
                    pin = m.group(1)
                    merge(pins, {f"{pin[:2]}{int(pin[2:])}": p})
                continue
            m = PIN.fullmatch(name)
            if name and not m:
                cols = None
                continue
            func = [col(f"func{i}") for i in range(4)]
            p = entry(func, **{k: col(*v) for k, v in FIELDS.items()})
            if not m:
                if any(func):
                    unnamed.append((port, p))
                continue
            if int(m.group(2)) > 31:
                cols = None
                continue
            pin = f"P{m.group(1)}{int(m.group(2))}"
            named.add(pin)
            pins.setdefault(pin, p)
        analog(pins, unnamed, named)
    return pins


STAMP = re.compile(r"[A-Z]{1,2}")  # the letters of a diagonal watermark
SUPPLY = re.compile(r"\w*(VDD|VCC)\w*")
PULL = re.compile(r"(?i)hiz|z|pull-?(up|down)|pu|pd")
FURNITURE = re.compile(r"Data Sheet|Copyright|Version \d|Semiconductor|"
                       r"Pin Description|GPIO Group|^\s*\(\d{4}")


def func_table(lines):
    """A datasheet with Func0-Func3 columns. A row's ball name, which ends
    in its GPIO and lists its functions, wraps onto the lines around it, as
    do its cells, and the columns drift from page to page, so each row
    places them by its own pull and power cells and keeps only the
    functions its name has."""
    pins, head, row, fit = {}, None, None, (1.0, 0.0)

    def close():
        nonlocal fit
        m = GPIO.search(row["name"])
        if not m:
            return
        if row["pull"] and row["power"]:
            (p, _), (w, _) = row["pull"], row["power"]
            a = (w - p) / (head["Power"] - head["Pull"])
            fit = (a, p - a * head["Pull"])
        a, b = fit
        at = [a * head[f"Func{i}"] + b for i in range(4)]
        func = [""] * 4
        for s, t in row["cand"]:
            i = min(range(4), key=lambda i: min(
                abs(s - at[i]), abs(s + len(t) / 2 - at[i] - 2.5 * a)))
            # a watermark letter can stick to the front of a cell
            t = next((t[c:] for c in range(3) if re.search(
                rf"(^|_){re.escape(t[c:])}(_|$)", row["name"])), "")
            if t:
                func[i] = func[i] or t
        ball = row["ball"]
        pkg = "bga" if re.match(r"[A-Z]", ball) else "qfn"
        pins[f"P{m.group(1)}{int(m.group(2))}"] = entry(
            func, reset=(row["pull"] or (0, ""))[1],
            power=(row["power"] or (0, ""))[1], **{pkg: ball})

    def fresh():
        return {"name": "", "ball": "", "pull": None, "power": None,
                "cand": []}

    for line in lines + [""]:
        if re.search(r"Func0\s+Func1\s+Func2\s+Func3", line):
            if row:
                close()
            head = {m.group(): m.start() for m in re.finditer(
                r"Ball Name|Pull|Func[0-3]|Power", line)}
            head = head if len(head) == 7 else None
            row, fit = None, (1.0, 0.0)
            continue
        if not head or line.startswith(("```", "<!--", "![")) or \
                FURNITURE.search(line):
            continue
        toks = [(m.start(), m.group()) for m in re.finditer(r"\S+", line)]
        drive = next((k for k, (_, t) in enumerate(toks)
                      if re.fullmatch(r"[\d.]+mA", t)), None)
        ball = drive is not None and \
            re.fullmatch(r"\d{1,3}|[A-Z]{1,2}\d{1,2}", toks[0][1]) and \
            toks[0][0] < head["Pull"] / 2
        # a finished row takes the cells printed under it, up to the next
        # row's first line
        if row and row["ball"] and GPIO.search(row["name"]) and (
                drive is not None or any(
                    s < head["Pull"] - 1 and re.fullmatch(r"[A-Z0-9_]+", t)
                    and not STAMP.fullmatch(t) for s, t in toks)):
            close()
            row = None
        if not toks:
            continue
        row = row or fresh()
        k = 0
        if ball:
            if row["ball"]:
                close()
                row = fresh()
            row["ball"], k = toks[0][1], 1
        for n, (s, t) in enumerate(toks[k:], k):
            if n == drive:
                continue
            if s >= head["Pull"] - 1 and PULL.fullmatch(t) and \
                    (drive is None or n < drive):
                row["pull"] = row["pull"] or (s, t)
            elif SUPPLY.fullmatch(t):
                row["power"] = row["power"] or (s, t)
            elif STAMP.fullmatch(t):
                continue
            elif s < head["Pull"] - 1 or (drive is not None and n < drive):
                if re.fullmatch(r"[A-Z0-9_]+", t):
                    row["name"] += t
            else:
                row["cand"].append((s, t.rstrip("_")))
    if row and head:
        close()
    return pins


DESC = re.compile(r"([A-Z][A-Z0-9_]*[A-Z0-9])\s?[:：]")
LOC = re.compile(r"[A-Z]{0,2}\d{1,3}")
POWER = re.compile(r"\w*(VDD|VCC)\w*")


def name_table(lines):
    """An older datasheet: a pin's function names, then its GPIO, in the
    description column ("PB06: GPIO group B bit 06"), with its location,
    IO cell and power on the lines around them, some of them wrapped."""
    pins, loc_x, pending, last = {}, None, [], -1
    # the columns each line was printed under: a pin can start on one page
    # and end on the next, which has its own
    under = []
    for n, line in enumerate(lines):
        header = "Pin Description" in line and "Power" in line
        if header:
            loc_x = line.find("Loc")
        under.append(loc_x)
        if header or loc_x is None:
            continue
        if re.match(r"\s*Table \d", line):
            pending = []
        m = DESC.search(line, 8)
        if not m or m.start() < 14:
            continue
        g = GPIO.fullmatch(m.group(1))
        if not g or "GPIO" not in line[m.end():m.end() + 8]:
            # the names column wins a digit typo ("DVP_D1 ... DVP_D0: DVP
            # data bit 1" on the T10)
            c = re.match(r"[A-Z][A-Z0-9_]*\b", line)
            x = m.group(1)
            if c and c.group() != x and \
                    re.sub(r"\d", "", c.group()) == re.sub(r"\d", "", x):
                x = c.group()
            pending.append((n, x))
            continue
        start = max((pending[0][0] if pending else n) - 1, last + 1)
        names = [x for _, x in pending]
        pending = []
        end = n + 1
        while end < min(n + 4, len(lines)) and lines[end].strip() and \
                not DESC.search(lines[end], 14):
            end += 1
        last = end - 1
        loc, cell, power, pw, pin = "", [], [], "", None
        for i in range(start, end):
            text, x = lines[i], under[i] if i < len(under) else loc_x
            # the names column has the GPIO right where the description
            # gets it wrong ("PB28 ... PA28: GPIO group B bit 28" on the T30)
            c = re.match(r"P[A-F]\d\d\b", text)
            pin = pin or (c and c.group())
            d = DESC.search(text, 14)
            right = d.start() if d else x + 16
            for t in re.finditer(r"\S+", text):
                s, tok = t.start(), t.group()
                if x - 6 <= s <= x + 3 and LOC.fullmatch(tok):
                    loc = loc or tok
                elif x + 3 < s < right:
                    if cell and re.fullmatch(r"[a-z]{1,2}", tok):
                        cell[-1] += tok
                    else:
                        cell.append(tok)
                elif s > x + 30:
                    power.append((s, tok))
        at = None
        for s, tok in power:
            if not pw and POWER.fullmatch(tok):
                pw, at = tok, s
            elif pw.endswith("_") and abs(s - at) < 3 and \
                    re.fullmatch(r"[A-Z0-9]{1,3}", tok):
                pw += tok
        cell = [c for c in dict.fromkeys(cell)
                if re.search(r"(?i)pull|rst|schmitt|slew", c)]
        pin = pin or m.group(1)
        pins.setdefault(f"{pin[:2]}{int(pin[2:])}", {
            "names": names, "loc": loc, "cell": " ".join(cell), "power": pw})
    return pins


# The function numbers the vendor 3.10 kernels select, which the older
# datasheets leave out (soc-t*/include/mach/platform.h of the T20 3.12.0
# SDK for the T10 and T20, the T21 1.0.33 and the T30 1.0.5 SDKs): a pin's
# name that starts with, or has a part equal to, the prefix takes the number
KERNEL = {
    "t10": "UART0 PB19-22 0, UART1 PB23-24 0, MSC0 PB0-5 0, MSC1 PC2-7 0, "
           "SSI0 PC11-16 0, SFC PA23-28 1, I2C0 PA12-13 1, I2C1 PB25-26 0, "
           "PWM0 PB17 0, PWM1 PB18 0, PWM2 PC8 0, PWM3 PC9 0, MCLK PA15 1, "
           "DVP PA0-11 1, DVP PA14 1, DVP PA16-17 1, DMIC PC11-12 1, "
           "DMIC PC15 1, GMAC PB6-11 0, GMAC PB13-16 0",
    "t21": "UART0 PB19-22 0, UART1 PB23-24 0, UART2 PC13-14 2, MSC0 PB0-5 0, "
           "MSC1 PC2-7 0, SSI0 PC8-9 0, SSI0 PC11-14 0, SSI1 PB8-11 1, "
           "SSI1 PB13-14 1, SFC PA23-28 1, I2C0 PA12-13 1, I2C1 PB25-26 0, "
           "I2C1 PC8-9 2, MCLK PA15 1, DRV_VBUS PB27 0, DVP PA0-11 1, "
           "DVP PA14 1, DVP PA16-17 1, GMAC PB6-11 0, GMAC PB13-16 0",
    "t30": "UART0 PB19-22 0, UART1 PB23-24 0, MSC0 PB0-5 0, MSC1 PC2-7 0, "
           "I2S PC18-24 0, SSI0 PC11-16 0, SSI1 PC19-24 1, SSI1 PD2-7 2, "
           "SFC PA23-28 1, "
           "I2C0 PA12-13 1, I2C1 PB25-26 0, I2C2 PC27-28 1, PWM0 PB17 0, "
           "PWM1 PB18 0, PWM2 PC8 0, PWM3 PC9 0, MCLK PA15 1, "
           "DRV_VBUS PC17 0, DVP PA0-11 1, DVP PA14 1, DVP PA16-17 1, "
           "DMIC PC8 2, DMIC PC25-26 2, GMAC PB6-11 0, GMAC PB13-16 0, "
           "TFT PD2-9 0, TFT PD12-19 0, TFT PD22-27 0, LCD PD8 0, "
           "SLCD PD2-7 1, SLCD PD9 1, SLCD PD12-17 1, SLCD PD19 1, "
           "SLCD PD22-25 1, SLCD PD27 1",
}
# soc-t20 selects what soc-t10 does, but for the OTG VBUS pin
KERNEL["t20"] = KERNEL["t10"]


def kernel(soc):
    """{pin: [(prefix, number)]} from KERNEL."""
    out = {}
    for item in KERNEL.get(soc, "").split(", "):
        if not item:
            continue
        prefix, pins, func = item.split()
        m = re.fullmatch(r"P([A-F])(\d+)(?:-(\d+))?", pins)
        for n in range(int(m.group(2)), int(m.group(3) or m.group(2)) + 1):
            out.setdefault(f"P{m.group(1)}{n}", []).append(
                (prefix, int(func)))
    return out


def bare(name):
    return name.rstrip("_#?").upper()


def numbered(soc, pins, refs):
    """Function numbers for an older datasheet's names, which come in order
    with the empty ones left out: certain where the vendor kernel selects
    one or the order leaves a name one number, else a guess."""
    known, out = kernel(soc), {}
    for pin, p in pins.items():
        names = p["names"][:4]
        k = len(names)
        fixed = {}
        for prefix, f in known.get(pin, []):
            alias = re.sub(r"^I2C", "SMB", prefix)
            hit = [j for j, x in enumerate(names)
                   if any(x.startswith(q) or q in x.split("_")
                          for q in (prefix, alias))]
            if len(hit) == 1:
                fixed[hit[0]] = f
        lo = [max([j] + [f + j - i for i, f in fixed.items() if i < j])
              for j in range(k)]
        hi = [min([3 - (k - 1 - j)] +
                  [f - (i - j) for i, f in fixed.items() if i > j])
              for j in range(k)]
        if any(a > b for a, b in zip(lo, hi)):
            print(f"{soc} {pin}: kernel numbers {fixed} don't fit {names}")
            fixed, lo = {}, list(range(k))
            hi = [3 - (k - 1 - j) for j in range(k)]
        ref = [[bare(f) for f in r[pin]["func"]] for r in refs if pin in r]
        func, prev = [""] * 4, -1
        for j, x in enumerate(names):
            if j in fixed or lo[j] == hi[j]:
                i = fixed.get(j, lo[j])
                func[i] = x
            else:
                i = next((r.index(bare(x)) for r in ref if bare(x) in r), -1)
                if not lo[j] <= i <= hi[j] or i <= prev:
                    i = max(lo[j], prev + 1)
                func[i] = x + "?"
            prev = i
        pkg = "bga" if re.match(r"[A-Z]", p["loc"]) else "qfn"
        out[pin] = entry(func, reset=p["cell"], power=p["power"],
                         **{pkg: p["loc"]})
    return out


def newest(docs, folder, pattern):
    found = [f for f in sorted(glob.glob(os.path.join(
        docs, folder, pattern + ".md")))
        if not f.endswith((".min.md", "_CN.md"))]
    return found[-1] if found else None


def build(docs, soc, refs):
    folder, patterns = SOURCES[soc]
    pins, used = {}, []
    for pattern in patterns:
        path = newest(docs, folder, pattern)
        if not path:
            continue
        text = open(path, encoding="utf-8").read()
        if "```csv" in text:
            got = sheet_pins(path)
        elif re.search(r"Func0\s+Func1", text):
            got = func_table(text.split("\n"))
        else:
            got = numbered(soc, name_table(text.split("\n")), refs)
        if got:
            merge(pins, got)
            used.append(os.path.basename(path)[:-3])
    return pins, used


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    docs = os.path.join(sys.argv[1], "text")
    socs = [s.lower() for s in sys.argv[2:]] or sorted(SOURCES)
    refs = [build(docs, r, [])[0] for r in REFERENCE]
    os.makedirs(OUT, exist_ok=True)
    for soc in socs:
        pins, used = build(docs, soc, refs)
        if not pins:
            print(f"{soc}: no pins found")
            continue
        order = sorted(pins, key=lambda k: (k[1], int(k[2:])))
        with open(os.path.join(OUT, f"{soc}.json"), "w") as f:
            json.dump({"soc": soc, "source": "; ".join(used),
                       "pins": {k: pins[k] for k in order}}, f, indent=1,
                      ensure_ascii=False)
            f.write("\n")
        print(f"{soc}: {len(pins)} pins from {'; '.join(used)}")


if __name__ == "__main__":
    main()
