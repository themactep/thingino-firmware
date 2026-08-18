#!/bin/sh
# Inject boot-window GPIO presets into a U-Boot leaf .dts at build time, read
# from the board's thingino.json. One gpio-hog child node is emitted per pin
# under its &gp<bank>, and U-Boot's gpio core drives them all right after DM
# init - board pins are held at a defined level from U-Boot until Linux takes
# over. Three sources, each with the level rule of its runtime consumer:
#
#   motors.*    - PTZ stepper phase pins (gpio_pan + gpio_tilt) parked at the
#                 kernel driver's de-energised level so the coils don't cook
#                 during the boot window: gpio_invert=false parks LOW,
#                 gpio_invert=true parks HIGH (motor.c power-off rule).
#                 SPI (is_spi) and focus-only units have no phase pins.
#
#   gpio.wlan   - Wi-Fi module power/enable/reset lines at the final resting
#                 level of the S36wireless.in sequence (S36 only replays it on
#                 3.10 kernels, late in boot; SDIO modules must be powered for
#                 the kernel MMC scan to see them). Accepts every shape S36
#                 does: bare pin (high), suffixed token ("47o" low / "47O"
#                 high / "47t" toggle), token sequences (last state per pin
#                 wins), {pin, active_low, toggle, action/mode, state/value}
#                 objects - active_low=true rests low, explicit state wins -
#                 or lists of those. A pin whose last action is a toggle
#                 depends on prior state and cannot be a static hog: skipped.
#                 An object's toggle flag only prepends a pulse and does not
#                 change the resting level.
#
#   gpio.mmc_power (list form only) - boards whose SD slot needs more than one
#                 supply/enable pin, [{pin, active_low}, ...], each driven at
#                 its power-on level (active_low=true -> LOW) like S09mmc
#                 does after the mmc driver loads. The single-pin object form
#                 is NOT handled here - inject-uboot-mmc-dt.sh turns it into a
#                 vmmc-supply regulator so the mmc core sequences slot power
#                 itself; a fixed regulator can only own one gpio, which is
#                 why multi-pin boards get plain hogs instead.
#
#   gpio.ircut (+ gpio.ircut_sub) - IR-cut filter coil pins parked at the
#                 /usr/sbin/ircut idle level so the solenoid is not left
#                 floating or energised through the boot window. Dual-pin
#                 boards rest both pins at idle between pulses and single-pin
#                 boards de-energise at the "open" level; both work out to
#                 active_low ? HIGH : LOW per pin. NOTE the ircut token
#                 suffix means polarity, not a drive level as in gpio.wlan:
#                 "57o" = active-low pin = idle HIGH ("57O" = active-high =
#                 idle LOW). Pin 999 is the tmi8152 kernel-shim sentinel (no
#                 gpio) and a -1 token disables the whole domain, exactly as
#                 the runtime script treats them.
#
#   gpio.speaker - the speaker amplifier enable line, held at its muted
#                 (inactive) level so the amp is not left floating through
#                 the boot window: the kernel codec module mutes it at probe
#                 for exactly that reason. Muted is the inverse of the active
#                 level, so active_low=true rests HIGH and a plain pin rests
#                 LOW. U-Boot's own codec driver drives this pin raw around
#                 playback rather than through the gpio uclass (see
#                 inject-uboot-audio-dt.sh, which feeds the same key to the
#                 codec node as ingenic,spk-gpio), so the hog does not fight
#                 it for ownership - it only defines the level until then.
#
# A pin that inject-uboot-mmc-dt.sh turns into a DT binding (gpio.mmc_cd ->
# cd-gpios, single-pin gpio.mmc_power (object or bare int) -> vmmc regulator, gpio.button_reset
# -> gpio-keys) is never hogged: a hog claims the gpio at DM init and the
# binding's own request then fails, breaking the subsystem that needed it
# (cinnado_b6 lists pin 61 as both mmc_cd and a motor phase - card-detect
# must win). Such pins are reported as skipped in the build log. Repeated
# pins within/across hog domains collapse to the first occurrence.
#
# Flags are emitted as GPIO_ACTIVE_HIGH (0) so the physical level is
# unambiguous and no dt-bindings include is needed. Hogs land in U-Boot
# proper only, not SPL.
#
# Usage: inject-uboot-gpio-dt.sh <thingino.json> <leaf.dts> <dt-name>
set -e

JSON="$1"
DTS="$2"
DT="$3"
[ -f "$JSON" ] && [ -f "$DTS" ] || exit 0

# Already injected on a previous incremental build?
grep -q 'thingino GPIO presets' "$DTS" && exit 0

# Emit "<name>:<pin>:<level>" tokens, or nothing when there is nothing to hog.
vals=$(
	python3 - "$JSON" 2>/dev/null <<'PY'
import json, sys

root = json.load(open(sys.argv[1]))
out = []  # (name, pin, level), first occurrence per (name, pin) ordered

def is_true(v):  # S36wireless/S09mmc bool_is_true
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, float)):
        return v == 1
    if isinstance(v, str):
        w = v.split()
        return bool(w) and w[0].lower() in ("1", "true", "yes", "on", "enable", "enabled")
    return False

# ---- motors: park pan/tilt phases at the kernel driver's off level --------
m = root.get("motors", {})
if not is_true(m.get("is_spi")):
    pins = []
    for axis in ("gpio_pan", "gpio_tilt"):
        v = m.get(axis)
        if isinstance(v, str):
            pins += [int(t) for t in v.split() if t.lstrip("-").isdigit() and int(t) >= 0]
        elif isinstance(v, int) and v >= 0:
            pins.append(v)
    park = 1 if is_true(m.get("gpio_invert")) else 0
    out += [("motor_park", p, park) for p in pins]

# ---- gpio.wlan: final resting level of the S36wireless sequence -----------
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

def token(tok):  # S36wireless parse_legacy_token -> (pin, level|None=toggle) | None
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

walk(root.get("gpio", {}).get("wlan"))
final, order = {}, []
for pin, lvl in events:
    if pin not in final:
        order.append(pin)
    final[pin] = lvl  # None = toggle-final = not expressible, dropped below
out += [("wlan", p, final[p]) for p in order if final[p] is not None]

# ---- gpio.mmc_power list form: multi-pin slot power at the on level -------
mp = root.get("gpio", {}).get("mmc_power")
if isinstance(mp, list):
    for e in mp:
        if isinstance(e, dict) and isinstance(e.get("pin"), int) and e["pin"] >= 0:
            out.append(("mmc_power", e["pin"], 0 if is_true(e.get("active_low")) else 1))

# ---- gpio.ircut / gpio.ircut_sub: park filter coil pins at idle -----------
def bool_flag(v, dflt):  # /usr/sbin/ircut bool_flag
    if isinstance(v, bool):
        return 1 if v else 0
    if v in (1, "1", "true", "TRUE", "on", "ON", "yes", "YES"):
        return 1
    if v in (0, "0", "false", "FALSE", "off", "OFF", "no", "NO"):
        return 0
    return dflt

def ircut_walk(v, default_al, acc):
    # mirrors /usr/sbin/ircut extract_node/parse_pin_token; acc = list of
    # (pin, active_low); returns False when a -1 token disables the domain
    if isinstance(v, dict):
        al = bool_flag(v.get("active_low"), default_al)
        return ircut_walk(v.get("pin"), al, acc)
    if isinstance(v, list):
        for e in v:
            if not ircut_walk(e, default_al, acc):
                return False
        return True
    if isinstance(v, bool) or v is None:
        return True
    for tok in (str(v).split() if not isinstance(v, int) else [str(v)]):
        if tok == "-1":
            return False
        if tok == "999":  # tmi8152 kernel shim, no gpio
            continue
        al = default_al
        if tok[-1] == "o":
            tok, al = tok[:-1], 1
        elif tok[-1] == "O":
            tok, al = tok[:-1], 0
        if tok.isdigit():
            acc.append((int(tok), al))
    return True

for key in ("ircut", "ircut_sub"):
    acc = []
    if ircut_walk(root.get("gpio", {}).get(key), 0, acc):
        out += [("ircut", p, 1 if al else 0) for p, al in acc]

# ---- gpio.speaker: hold the speaker amp muted through the boot window ----
sp = root.get("gpio", {}).get("speaker")
if isinstance(sp, dict):
    sp_pin, sp_al = sp.get("pin"), is_true(sp.get("active_low"))
elif isinstance(sp, int) and not isinstance(sp, bool):
    sp_pin, sp_al = sp, False	# short notation: bare int = active-high pin
else:
    sp_pin, sp_al = None, False
if isinstance(sp_pin, int) and not isinstance(sp_pin, bool) and sp_pin >= 0:
    out.append(("spk_mute", sp_pin, 1 if sp_al else 0))

# Pins inject-uboot-mmc-dt.sh turns into DT bindings - the binding's gpio
# request must win, so these are never hogged (level 's' = skip note).
g = root.get("gpio", {})
reserved = set()
cd = g.get("mmc_cd")
if isinstance(cd, int) and cd >= 0:
    reserved.add(cd)
if isinstance(mp, dict) and isinstance(mp.get("pin"), int) and mp["pin"] >= 0:
    reserved.add(mp["pin"])
elif isinstance(mp, int) and not isinstance(mp, bool) and mp >= 0:
    reserved.add(mp)  # short notation: bare int = active-high pin
br = g.get("button_reset")
bp = br.get("pin") if isinstance(br, dict) else br
if isinstance(bp, int) and bp >= 0:
    reserved.add(bp)

seen = set()
final_out = []
for name, pin, lvl in out:
    if pin in seen:
        continue
    seen.add(pin)
    final_out.append((name, pin, "s" if pin in reserved else lvl))
if final_out:
    print(" ".join("%s:%s:%s" % t for t in final_out))
PY
)
[ -n "$vals" ] || exit 0

# gpio number -> bank label letter (PA=a..PE=e), empty if out of range
bank() {
	case $(($1 / 32)) in
		0) echo a ;; 1) echo b ;; 2) echo c ;; 3) echo d ;; 4) echo e ;; *) echo "" ;;
	esac
}

emitted=""
{
	printf '\n/* thingino GPIO presets: hold board pins at their runtime level through\n'
	printf ' * the boot window (motors / gpio.wlan / gpio.mmc_power / gpio.ircut /\n'
	printf ' * gpio.speaker). */\n'
	for TOK in $vals; do
		NAME=${TOK%%:*}
		REST=${TOK#*:}
		PIN=${REST%%:*}
		LVL=${REST##*:}
		if [ "$LVL" = s ]; then
			echo "U-Boot: NOT hogging $NAME pin $PIN - owned by an MMC/button DT binding" >&2
			continue
		fi
		PB=$(bank "$PIN")
		[ -n "$PB" ] || continue
		if [ "$LVL" = 1 ]; then STATE="output-high"; else STATE="output-low"; fi
		printf '&gp%s {\n' "$PB"
		printf '\t%s_%s {\n' "$NAME" "$PIN"
		printf '\t\tgpio-hog;\n'
		printf '\t\t%s;\n' "$STATE"
		printf '\t\tgpios = <%s 0>;\t/* GPIO_ACTIVE_HIGH */\n' "$((PIN % 32))"
		printf '\t};\n'
		printf '};\n'
		emitted="$emitted $NAME/$PIN=$STATE"
	done
} >>"$DTS"

[ -n "$emitted" ] && echo "U-Boot: injected GPIO presets:$emitted"
exit 0
