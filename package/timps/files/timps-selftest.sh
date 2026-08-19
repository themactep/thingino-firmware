#!/bin/sh
# shellcheck disable=SC2015
# timps-selftest - on-device smoke test of the timps HTTP API and features.
# Run on the camera:  timps-selftest        (or: timps-selftest -v  for bodies)
# Exits 0 when nothing FAILED (warnings are non-fatal: they usually mean a
# feature is simply not enabled/available on this build or no SD is mounted).

CONF=/etc/timps.conf
VERBOSE=0
[ "$1" = "-v" ] && VERBOSE=1

port=$(sed -n 's/^[[:space:]]*http\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
[ -n "$port" ] || port=8880
https=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
case "$https" in 1 | true | yes | on)
	scheme=https
	K="-k"
	;;
*)
	scheme=http
	K=""
	;;
esac
tok=$(head -n1 /run/timps.token 2>/dev/null | tr -cd '0-9A-Za-z')
BASE="$scheme://127.0.0.1:$port"
AUTH="X-Timps-Token: $tok"

pass=0
fail=0
ok() {
	echo "  [PASS] $1"
	pass=$((pass + 1))
}
bad() {
	echo "  [FAIL] $1"
	fail=$((fail + 1))
}
warn() { echo "  [WARN] $1"; }
get() { curl -s $K -m 5 -H "$AUTH" "$BASE$1"; }
post() { curl -s $K -m 5 -H "$AUTH" -X POST "$BASE/control" -d "$1" >/dev/null 2>&1; }
# like post() but prints the HTTP status - POST /control grades its answer, so
# the status alone now carries a verdict worth asserting on
post_code() { curl -s $K -m 5 -H "$AUTH" -o /dev/null -w '%{http_code}' -X POST "$BASE/control" -d "$1" 2>/dev/null; }

if [ -n "$tok" ]; then tokstate=present; else tokstate=MISSING; fi
echo "timps selftest -> $BASE  (token: $tokstate)"
command -v curl >/dev/null 2>&1 || {
	echo "curl not found"
	exit 1
}

# ---- /control + sections ----
CTL=$(get /control)
[ "$VERBOSE" = 1 ] && echo "$CTL" | head -c 400 && echo
echo "$CTL" | grep -q '"caps"' && ok "/control responds" || {
	bad "/control not responding"
	echo "timps running? try: /etc/init.d/S95timps status"
}
for k in image audio video osd motion privacy record daynight; do
	echo "$CTL" | grep -q "\"$k\":" && ok "section: $k" || bad "section: $k missing"
done

# ---- caps ----
echo "$CTL" | grep -q '"privacy":{"available":1' && ok "caps.privacy" || bad "caps.privacy"
echo "$CTL" | grep -q '"record":{"available":1' && ok "caps.record" || bad "caps.record"
if echo "$CTL" | grep -o '"motion":{"available":[01]' | grep -q ':1'; then
	ok "motion available"
else warn "motion not available (SoC/SDK has no IMP_IVS move API)"; fi

# ---- media endpoints ----
sz=$(curl -s $K -m 5 -H "$AUTH" "$BASE/snapshot.jpg?chn=0" | wc -c)
[ "$sz" -gt 200 ] && ok "snapshot.jpg ($sz bytes)" || bad "snapshot.jpg empty"
mp=$(curl -s $K -m 3 -H "$AUTH" "$BASE/stream.mp4?chn=1" | head -c 64 | wc -c)
[ "$mp" -gt 0 ] && ok "stream.mp4 flowing" || bad "stream.mp4 no data"
mj=$(curl -s $K -m 3 -H "$AUTH" "$BASE/stream.mjpeg?chn=1" | head -c 64 | wc -c)
[ "$mj" -gt 0 ] && ok "stream.mjpeg flowing" || warn "stream.mjpeg no data"

# ---- /events push ----
ev=$(curl -s $K -m 4 -N "$BASE/events?stream=stats&token=$tok" 2>/dev/null | head -c 200)
echo "$ev" | grep -q 'event:' && ok "/events pushing" || warn "/events no frame (events.enabled=0?)"

# ---- POST /control write grading ----
# the daemon used to answer 200 {"ok":true} to garbage and typos alike, so no
# test could fail here. All three probes are deliberately non-mutating: each
# applies NOTHING, which is exactly what the status asserts.
#
# 400/422/409 are three DIFFERENT diagnoses and the split is the point (timps
# 2eadf1e, "control: say what this build can do, and stop overloading 422"):
#   400 - the body was not a JSON object          -> the caller is malformed
#   422 - parsed, no field known to THIS build    -> the key NAMES are wrong;
#         retrying unchanged can never succeed
#   409 - names known, every value refused        -> re-send with valid values
# Asserting each separately is what catches a daemon that has regressed to
# answering one code for two conditions - the state this test was written for.
#
# The 422 probe is also why the daemon KEPT 422 for the unknown-field case
# rather than renumbering it: fielded copies of this script assert 422 here,
# and moving it would have turned every deployed selftest red.
c=$(post_code 'not json')
[ "$c" = "400" ] && ok "POST garbage -> 400" || bad "POST garbage -> $c (want 400)"
c=$(post_code '{"selftest_unknown_field":1}')
[ "$c" = "422" ] && ok "POST unknown field -> 422" || bad "POST unknown field -> $c (want 422)"
# null on a numeric field: image.brightness is known to every build, and null
# is refused for every type (an empty string would NOT do here - since timps
# 7893a1a "" is a valid "clear this" on STRING fields).
c=$(post_code '{"image":{"brightness":null}}')
[ "$c" = "409" ] && ok "POST refused value -> 409" || bad "POST refused value -> $c (want 409)"

# ---- privacy round-trip (uses region 3 so it won't clobber a real mask 0) ----
post '{"privacy":{"0":{"3":{"enabled":1,"x":8,"y":8,"w":48,"h":48,"color":"0xFF0000FF"}}}}'
get /control | grep -q '"3":{"enabled":1,"x":8,"y":8,"w":48,"h":48' && ok "privacy set + readback" || bad "privacy set/readback"
post '{"privacy":{"0":{"3":{"enabled":0,"w":0,"h":0}}}}'

# ---- recording start/stop ----
post '{"record":{"active":1}}'
sleep 2
rec=$(get /control | grep -o '"record":{[^}]*}')
[ "$VERBOSE" = 1 ] && echo "  record=$rec"
echo "$rec" | grep -q '"recording":1' && ok "recording started" || warn "recording not active (is record.dir mounted/writable?)"
post '{"record":{"active":0}}'

# ---- SRT listener ----
srten=$(sed -n 's/^[[:space:]]*srt\.enabled[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
srtport=$(sed -n 's/^[[:space:]]*srt\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
[ -n "$srtport" ] || srtport=9000
case "$srten" in
	1 | true | yes | on)
		if netstat -lun 2>/dev/null | grep -q ":$srtport\b"; then
			ok "SRT listening on udp/$srtport"
		else warn "SRT udp/$srtport not listening (libsrt build? check logread)"; fi
		;;
	*) warn "SRT disabled (srt.enabled not set)" ;;
esac

# ---- HTTPS note ----
[ "$scheme" = https ] && ok "HTTPS scheme active" || echo "  [info] plain HTTP (http.https not set)"

echo "--------------------------------------------------"
echo "timps selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
