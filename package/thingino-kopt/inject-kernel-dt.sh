#!/bin/sh
# Inject per-board MMC and Wi-Fi device-tree nodes into the mainline (7.x)
# kernel's generic board .dts at build time, read from the board's
# thingino.json. This is the kernel counterpart of the U-Boot injectors
# (package/thingino-uboot/inject-uboot-{mmc,gpio}-dt.sh): the GPIOs are
# board-specific while the kernel's device tree is one generic board per SoC,
# so they cannot live in the shared .dts and go into a per-board .dtsi that is
# #included from this build's copy of it (the way inject-usb-dt.sh does it).
# The fragment is rewritten only when it changes, so an unchanged board does
# not rebuild the dtb. The tree that is edited is the one the kernel config
# names in CONFIG_BUILTIN_DTB_NAME.
#
#   gpio.wlan     - an SDIO Wi-Fi module's power/enable/reset line(s), with the
#                   same json shapes as the U-Boot injector and S36wireless:
#                   bare pin (high enables), suffixed token ("47o" low enables,
#                   "47O" high), {pin, active_low, state/value} objects, or
#                   lists of those; the last level a pin is driven to is the
#                   level that enables the module. It becomes an
#                   mmc-pwrseq-simple on MSC1 (reset-gpios, asserted while the
#                   module is off) and enables MSC1 as a non-removable 4-bit
#                   host, so the mmc core powers the module and finds it at
#                   probe: a non-removable host scans once, so a userspace
#                   gpio write afterwards would be too late. Only when the
#                   Wi-Fi module is SDIO (the interface is passed in); USB and
#                   PCIe modules are left alone. A pin whose last action is a
#                   toggle depends on prior state and cannot be a static level:
#                   it is skipped.
#   gpio.mmc_power - the SD slot supply, as a regulator-fixed and the slot's
#                   vmmc-supply. Same short notation as inject-uboot-mmc-dt.sh:
#                   a bare int is an active-high pin, an object
#                   {pin, active_low} states the polarity. The list form (more
#                   than one supply pin) is not a single regulator and is left
#                   alone. A regulator the generic board already declares as
#                   the &vmmc label is retargeted instead of duplicated, so
#                   two regulators never claim the same gpio. It is named
#                   "sd-power", never "vmmc": a host without a vmmc-supply
#                   (the SDIO Wi-Fi on MSC1) would otherwise find it by name
#                   and switch the SD slot as its own supply.
#   gpio.mmc_cd   - the SD card detect, active low with the pull-up on the pin,
#                   closed to ground by a card, like the U-Boot one: it
#                   replaces broken-cd and any detect the generic board has.
#   gpio.sensor_switch - the MIPI switch pad of a two- or three-sensor T23
#                   (7 = PA7, 54 = PB22, 62 = PB30): the ISP node gets a
#                   "mipi-switch" pin state with the generic board's
#                   pins_cim_mipi_switch on that pad, which the ISP module
#                   selects when the VIC takes the pad over.
#   bus-width     - how many SD data lines the board routes, passed in (the
#                   same BR2_PACKAGE_THINGINO_KOPT_MMC0_1BIT fact U-Boot gets).
#   dmic          - "1" when the profile has a digital microphone
#                   (BR2_THINGINO_AUDIO_DMIC): enables the generic board's
#                   &dmic, which it leaves disabled because its pins are often
#                   GPIOs on boards without one.
#
# Numeric gpio flags are emitted (ACTIVE_LOW=1) so the fragment needs no
# dt-bindings include. What the generic board does not describe is skipped
# with a message, never guessed: no &msc1 node with its pins, no gpio bank
# label, no pinctrl line on &msc0.
#
# Usage: inject-kernel-dt.sh <thingino.json> <linux-dir> [wifi-interface] [bus-width] [dmic]
set -e

JSON="$1"
LINUX="$2"
WIFI="$3"
BUSW="$4"
DMIC="$5"
DTSDIR="$LINUX/arch/mips/boot/dts/ingenic"

[ -f "$LINUX/.config" ] && [ -d "$DTSDIR" ] || exit 0
name=$(sed -n 's/^CONFIG_BUILTIN_DTB_NAME="\(.*\)"/\1/p' "$LINUX/.config")
name=${name##*/}
dts="$DTSDIR/$name.dts"
[ -n "$name" ] && [ -f "$dts" ] || exit 0

inc="$name-thingino-board.dtsi"
rm -f "$DTSDIR/$inc.tmp"
if [ -f "$JSON" ] || [ -n "$BUSW" ] || [ -n "$DMIC" ]; then
	python3 - "$JSON" "$dts" "$WIFI" "$BUSW" "$DMIC" >"$DTSDIR/$inc.tmp" <<'PY'
import json, os, re, sys

jpath, dts, wifi, busw, dmic = sys.argv[1:6]
name = os.path.basename(dts)
root = json.load(open(jpath)) if os.path.isfile(jpath) else {}
g = root.get("gpio", {})


def load(path, seen):
    if path in seen or not os.path.isfile(path):
        return ""
    seen.add(path)
    s = open(path).read()
    for inc in re.findall(r'^\s*#include\s+"([^"]+)"', s, re.M):
        s += "\n" + load(os.path.join(os.path.dirname(path), inc), seen)
    return s


tree = load(dts, set())
out = []


def say(msg):
    print("thingino-kopt: %s: %s" % (name, msg), file=sys.stderr)


def bank(pin):  # PA..PE -> gpa..gpe label, None when the tree has none
    label = "gp" + "abcde"[pin // 32] if pin // 32 < 5 else None
    if label and re.search(r"^\s*%s\s*:" % label, tree, re.M):
        return label
    return None


def is_true(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v == 1
    if isinstance(v, str):
        w = v.split()
        return bool(w) and w[0].lower() in ("1", "true", "yes", "on", "enable", "enabled")
    return False


# ---- gpio.wlan: the level that enables the module (see the U-Boot injector) --
def norm_state(v):
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, int):
        return v if v in (0, 1) else None
    if isinstance(v, str):
        w = v.split()
        if not w:
            return None
        if w[0] in ("0", "1"):
            return int(w[0])
        return {"true": 1, "high": 1, "on": 1, "enable": 1, "enabled": 1,
                "false": 0, "low": 0, "off": 0, "disable": 0, "disabled": 0}.get(w[0].lower())
    return None


def token(tok):  # S36wireless parse_legacy_token -> (pin, level | None = toggle)
    if tok and tok[-1] in "oOtT~":
        pin, sfx = tok[:-1], tok[-1]
    else:
        pin, sfx = tok, ""
    if not pin.isdigit():
        return None
    return (int(pin), {"o": 0, "O": 1, "": 1}.get(sfx))


def obj(o):  # S36wireless emit_wlan_object_path final state
    pin = o.get("pin")
    if isinstance(pin, dict):
        al = pin.get("active_low", o.get("active_low"))
        pin = pin.get("pin")
    else:
        al = o.get("active_low")
    if isinstance(pin, str) and pin.isdigit():
        pin = int(pin)
    if isinstance(pin, bool) or not isinstance(pin, int) or pin < 0:
        return None
    action = o.get("action") or o.get("mode")
    state = o.get("state")
    if state in (None, ""):
        state = o.get("value")
    if not action and isinstance(state, str) and state.lower() in ("toggle", "~"):
        action, state = "toggle", None
    if action == "toggle":
        return (pin, None)
    if state in (None, ""):
        return (pin, 0 if is_true(al) else 1)
    s = norm_state(state)
    return (pin, s) if s is not None else None


events = []


def walk(v):
    if isinstance(v, dict):
        r = obj(v)
        r and events.append(r)
    elif isinstance(v, list):
        for e in v:
            walk(e)
    elif isinstance(v, int) and not isinstance(v, bool):
        r = token(str(v))
        r and events.append(r)
    elif isinstance(v, str):
        for t in v.split():
            r = token(t)
            r and events.append(r)


def msc1_has_pins():
    m = re.search(r"^&msc1\s*\{(.*?)^\};", tree, re.M | re.S)
    return bool(m and "pinctrl-0" in m.group(1))


if wifi == "sdio" and "wlan" in g:
    walk(g["wlan"])
    final, order = {}, []
    for pin, lvl in events:
        if pin not in order:
            order.append(pin)
        final[pin] = lvl
    pins = [(p, final[p]) for p in order if final[p] is not None]
    cells = []
    for p, lvl in pins:
        b = bank(p)
        if b is None:
            say("gpio.wlan pin %d has no gpio bank label, skipped" % p)
            continue
        # reset-gpios is asserted while the module is off: asserted must be
        # the level that disables it, so a high-enabled pin is ACTIVE_LOW
        cells.append("<&%s %d %d>" % (b, p % 32, 1 if lvl == 1 else 0))
        say("gpio.wlan %d enables at %s" % (p, "high" if lvl == 1 else "low"))
    if not cells:
        say("gpio.wlan: no static level to use, no Wi-Fi host")
    elif not msc1_has_pins():
        say("no &msc1 with its pins in the generic board, no Wi-Fi host")
    else:
        out.append("/ {\n\twlan_pwrseq: msc1-pwrseq {\n\t\tcompatible = \"mmc-pwrseq-simple\";\n"
                   "\t\treset-gpios = %s;\n\t\tpost-power-on-delay-ms = <100>;\n\t};\n};\n" % ", ".join(cells))
        out.append("&msc1 {\t/* SDIO Wi-Fi module */\n\tstatus = \"okay\";\n\tbus-width = <4>;\n"
                   "\tnon-removable;\n\tmmc-pwrseq = <&wlan_pwrseq>;\n};\n")

# ---- gpio.mmc_power: slot supply, single pin only -------------------------
mp = g.get("mmc_power")
if isinstance(mp, dict):
    pin, al = mp.get("pin"), is_true(mp.get("active_low"))
elif isinstance(mp, int) and not isinstance(mp, bool) and mp >= 0:
    pin, al = mp, False
else:
    pin, al = None, False
if isinstance(mp, list):
    say("gpio.mmc_power is a list, not a single supply, left alone")
if isinstance(pin, int) and not isinstance(pin, bool) and pin >= 0:
    b = bank(pin)
    if b is None:
        say("gpio.mmc_power pin %d has no gpio bank label, skipped" % pin)
    else:
        gpio = "gpio = <&%s %d %d>;" % (b, pin % 32, 1 if al else 0)
        # without enable-active-high the gpio core treats the pin as active low
        eah = "" if al else "\n\tenable-active-high;"
        if re.search(r"^\s*vmmc\s*:", tree, re.M):
            out.append("&vmmc {\t/* MMC slot supply, board gpio.mmc_power=%d */\n\tregulator-name = \"sd-power\";\n\t%s%s\n};\n" % (pin, gpio, eah or "\n\t/delete-property/ enable-active-high;"))
        else:
            out.append("/ {\n\tvmmc: regulator-vmmc {\t/* MMC slot supply, board gpio.mmc_power=%d */\n"
                       "\t\tcompatible = \"regulator-fixed\";\n\t\tregulator-name = \"sd-power\";\n"
                       "\t\tregulator-min-microvolt = <3300000>;\n\t\tregulator-max-microvolt = <3300000>;\n"
                       "\t\t%s%s\n\t\tstartup-delay-us = <100000>;\n\t};\n};\n" % (pin, gpio, eah.replace("\n\t", "\n\t\t")))
        out.append("&msc0 {\n\tvmmc-supply = <&vmmc>;\n};\n")
        say("gpio.mmc_power %d (%s)" % (pin, "active low" if al else "active high"))

# ---- gpio.mmc_cd and bus-width on the card slot ---------------------------
cd = g.get("mmc_cd")
msc0 = []
if isinstance(cd, int) and not isinstance(cd, bool) and cd >= 0:
    b = bank(cd)
    blk = re.search(r"^&msc0\s*\{(.*?)^\};", tree, re.M | re.S)
    m = re.search(r"pinctrl-0\s*=\s*<([^>]*)>", blk.group(1)) if blk else None
    if b is None:
        say("gpio.mmc_cd pin %d has no gpio bank label, skipped" % cd)
    elif not m:
        say("no pinctrl-0 on &msc0 in the generic board, gpio.mmc_cd skipped")
    else:
        pn = "P%s%d" % ("ABCDE"[cd // 32], cd % 32)
        out.append("&pinctrl {\n\tpins_mmc0_cd: mmc0-cd {\t/* pull-up: a card closes the detect to ground */\n"
                   "\t\tpins = \"%s\";\n\t\tbias-pull-up;\n\t};\n};\n" % pn)
        msc0 += ["/delete-property/ broken-cd;", "cd-gpios = <&%s %d 1>;" % (b, cd % 32),
                 "pinctrl-0 = <%s>, <&pins_mmc0_cd>;" % m.group(1).strip()]
        say("gpio.mmc_cd %d" % cd)
if busw in ("1", "4", "8"):
    msc0.append("bus-width = <%s>;" % busw)
if msc0:
    out.append("&msc0 {\t/* the card slot */\n" + "".join("\t%s\n" % p for p in msc0) + "};\n")

# ---- gpio.sensor_switch: the VIC's MIPI switch pad --------------------------
sw = g.get("sensor_switch")
sw_groups = {7: "cim-mipi-switch-a7", 54: "cim-mipi-switch-b22", 62: "cim-mipi-switch-b30"}
if isinstance(sw, int) and not isinstance(sw, bool):
    blk = re.search(r"^&isp\s*\{(.*?)^\};", tree, re.M | re.S)
    m = re.search(r"pinctrl-0\s*=\s*<([^>]*)>", blk.group(1)) if blk else None
    if sw not in sw_groups:
        say("gpio.sensor_switch %d is not a VIC switch pad (7, 54, 62), skipped" % sw)
    elif not re.search(r"^\s*pins_cim_mipi_switch\s*:", tree, re.M) or not m:
        say("no pins_cim_mipi_switch or no pinctrl-0 on &isp in the generic board, "
            "gpio.sensor_switch skipped")
    else:
        out.append("&pins_cim_mipi_switch {\n\tgroups = \"%s\";\n};\n" % sw_groups[sw])
        out.append("&isp {\t/* the VIC's MIPI switch, board gpio.sensor_switch=%d */\n"
                   "\tpinctrl-names = \"default\", \"mipi-switch\";\n"
                   "\tpinctrl-1 = <%s>, <&pins_cim_mipi_switch>;\n};\n" % (sw, m.group(1).strip()))
        say("gpio.sensor_switch %d" % sw)

# ---- the DMIC: only on a profile that has one ------------------------------
if dmic == "1":
    if re.search(r"^\s*dmic\s*:", tree, re.M):
        out.append("&dmic {\t/* BR2_THINGINO_AUDIO_DMIC */\n\tstatus = \"okay\";\n};\n")
        say("DMIC enabled")
    else:
        say("no dmic node in the generic board, DMIC left alone")

if out:
    print("/* Generated by thingino-kopt from the board's thingino.json. */\n")
    print("\n".join(out), end="")
PY
fi

if [ -s "$DTSDIR/$inc.tmp" ]; then
	if cmp -s "$DTSDIR/$inc.tmp" "$DTSDIR/$inc"; then
		rm -f "$DTSDIR/$inc.tmp"
	else
		mv "$DTSDIR/$inc.tmp" "$DTSDIR/$inc"
	fi
	grep -q "#include \"$inc\"" "$dts" || printf '\n#include "%s"\n' "$inc" >>"$dts"
else
	rm -f "$DTSDIR/$inc.tmp" "$DTSDIR/$inc"
	sed -i "/#include \"$inc\"/d" "$dts"
fi
exit 0
