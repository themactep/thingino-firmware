#!/bin/sh
# Inject Wi-Fi module GPIO preset gpio-hogs into a U-Boot leaf .dts at build
# time, read from the board's thingino.json gpio.wlan entry.
#
# Some Wi-Fi modules need their power/enable/reset line at a defined level
# before Linux is up: SDIO parts must be powered so the kernel's MMC scan can
# enumerate them, and until S36wireless runs (3.10 kernels only, late in boot)
# the pin sits at whatever the SoC reset default happens to be. Hogging the pin
# in U-Boot drives it through the whole boot window.
#
# gpio.wlan comes in every shape S36wireless.in accepts: a bare pin number
# (drive high), a suffixed token ("47o" low, "47O" high, "47t"/"47T"/"47~"
# toggle), a token sequence ("47O 47o"), an object {pin, active_low, toggle,
# action/mode, state/value} - active_low=true parks low, an explicit
# state/value wins - or a list of those. The hog level is the FINAL resting
# level of that sequence, i.e. the level the runtime script would leave the
# pin at; the runtime still replays any pulse on top of it. A toggle depends
# on prior state and cannot be expressed as a static hog, so a pin whose last
# action is a toggle is skipped; an object's "toggle": true flag only
# prepends a pulse and does not change the resting level. Flags are emitted
# as GPIO_ACTIVE_HIGH (0) so the physical level is unambiguous and no
# dt-bindings include is needed.
#
# Usage: inject-uboot-wlan-dt.sh <thingino.json> <leaf.dts> <dt-name>
set -e

JSON="$1"; DTS="$2"; DT="$3"
[ -f "$JSON" ] && [ -f "$DTS" ] || exit 0

# Already injected on a previous incremental build?
grep -q 'Wi-Fi module GPIO preset' "$DTS" && exit 0

# Emit "<pin>:<level> <pin>:<level> ...", or nothing when there is nothing
# expressible to preset.
vals=$(python3 - "$JSON" 2>/dev/null <<'PY'
import json, sys

def is_true(v):  # S36wireless bool_is_true
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v == 1
    if isinstance(v, str):
        w = v.split()
        return bool(w) and w[0].lower() in ("1", "true", "yes", "on", "enable", "enabled")
    return False

def norm_state(v):  # S36wireless normalize_state_value; None = invalid
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

def token(tok):  # S36wireless parse_legacy_token -> (pin, level) | (pin, None)=toggle | None
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

walk(json.load(open(sys.argv[1])).get("gpio", {}).get("wlan"))
final, order = {}, []
for pin, lvl in events:
    if pin not in final:
        order.append(pin)
    final[pin] = lvl
out = [(p, final[p]) for p in order if final[p] is not None]
if out:
    print(" ".join("%d:%d" % pl for pl in out))
PY
)
[ -n "$vals" ] || exit 0

# gpio number -> bank label letter (PA=a..PE=e), empty if out of range
bank() {
	case $(( $1 / 32 )) in
	0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

emitted=""
{
	printf '\n/* Wi-Fi module GPIO preset: drive the wlan power/enable pins to their\n'
	printf ' * runtime resting level through boot (board thingino.json gpio.wlan). */\n'
	for PAIR in $vals; do
		PIN=${PAIR%%:*}
		LVL=${PAIR##*:}
		PB=$(bank "$PIN")
		[ -n "$PB" ] || continue
		if [ "$LVL" = 1 ]; then STATE="output-high"; else STATE="output-low"; fi
		printf '&gp%s {\n' "$PB"
		printf '\twlan_%s {\n' "$PIN"
		printf '\t\tgpio-hog;\n'
		printf '\t\t%s;\n' "$STATE"
		printf '\t\tgpios = <%s 0>;\t/* GPIO_ACTIVE_HIGH */\n' "$(( PIN % 32 ))"
		printf '\t};\n'
		printf '};\n'
		emitted="$emitted $PIN=$STATE"
	done
} >> "$DTS"

[ -n "$emitted" ] && echo "U-Boot: injected Wi-Fi GPIO preset:$emitted"
exit 0
