#!/bin/sh
# shellcheck disable=SC2015

CONF=/etc/timps.conf
VERBOSE=0
[ "$1" = "-v" ] && VERBOSE=1

port=$(sed -n 's/^[[:space:]]*http\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' "$CONF" 2>/dev/null | head -n1)
[ -n "$port" ] || port=8880
https=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]')
case "$https" in 1 | 2 | true | yes | on)
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
post_code() { curl -s $K -m 5 -H "$AUTH" -o /dev/null -w '%{http_code}' -X POST "$BASE/control" -d "$1" 2>/dev/null; }

if [ -n "$tok" ]; then tokstate=present; else tokstate=MISSING; fi
echo "timps selftest -> $BASE  (token: $tokstate)"
command -v curl >/dev/null 2>&1 || {
	echo "curl not found"
	exit 1
}

CTL=$(get /control)
[ "$VERBOSE" = 1 ] && echo "$CTL" | head -c 400 && echo
echo "$CTL" | grep -q '"caps"' && ok "/control responds" || {
	bad "/control not responding"
	echo "timps running? try: /etc/init.d/S95timps status"
}
for k in image audio video osd motion privacy record daynight; do
	echo "$CTL" | grep -q "\"$k\":" && ok "section: $k" || bad "section: $k missing"
done

echo "$CTL" | grep -q '"privacy":{"available":1' && ok "caps.privacy" || bad "caps.privacy"
echo "$CTL" | grep -q '"record":{"available":1' && ok "caps.record" || bad "caps.record"
if echo "$CTL" | grep -o '"motion":{"available":[01]' | grep -q ':1'; then
	ok "motion available"
else warn "motion not available (SoC/SDK has no IMP_IVS move API)"; fi

sz=$(curl -s $K -m 5 -H "$AUTH" "$BASE/snapshot.jpg?chn=0" | wc -c)
[ "$sz" -gt 200 ] && ok "snapshot.jpg ($sz bytes)" || bad "snapshot.jpg empty"
mp=$(curl -s $K -m 3 -H "$AUTH" "$BASE/stream.mp4?chn=1" | head -c 64 | wc -c)
[ "$mp" -gt 0 ] && ok "stream.mp4 flowing" || bad "stream.mp4 no data"
mj=$(curl -s $K -m 3 -H "$AUTH" "$BASE/stream.mjpeg?chn=1" | head -c 64 | wc -c)
[ "$mj" -gt 0 ] && ok "stream.mjpeg flowing" || warn "stream.mjpeg no data"

ev=$(curl -s $K -m 4 -N "$BASE/events?stream=stats&token=$tok" 2>/dev/null | head -c 200)
echo "$ev" | grep -q 'event:' && ok "/events pushing" || warn "/events no frame (events.enabled=0?)"

c=$(post_code 'not json')
[ "$c" = "400" ] && ok "POST garbage -> 400" || bad "POST garbage -> $c (want 400)"
c=$(post_code '{"selftest_unknown_field":1}')
[ "$c" = "422" ] && ok "POST unknown field -> 422" || bad "POST unknown field -> $c (want 422)"
c=$(post_code '{"image":{"brightness":null}}')
[ "$c" = "409" ] && ok "POST refused value -> 409" || bad "POST refused value -> $c (want 409)"

post '{"privacy":{"0":{"3":{"enabled":1,"x":8,"y":8,"w":48,"h":48,"color":"0xFF0000FF"}}}}'
get /control | grep -q '"3":{"enabled":1,"x":8,"y":8,"w":48,"h":48' && ok "privacy set + readback" || bad "privacy set/readback"
post '{"privacy":{"0":{"3":{"enabled":0,"w":0,"h":0}}}}'

post '{"record":{"active":1}}'
sleep 2
rec=$(get /control | grep -o '"record":{[^}]*}')
[ "$VERBOSE" = 1 ] && echo "  record=$rec"
echo "$rec" | grep -q '"recording":1' && ok "recording started" || warn "recording not active (is record.dir mounted/writable?)"
post '{"record":{"active":0}}'

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

[ "$scheme" = https ] && ok "HTTPS scheme active" || echo "  [info] plain HTTP (http.https not set)"

echo "--------------------------------------------------"
echo "timps selftest: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
