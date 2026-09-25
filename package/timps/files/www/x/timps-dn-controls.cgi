#!/bin/sh
# shellcheck disable=SC1091,SC3043
# daynight.controls in thingino.json: what /usr/sbin/daynight toggles when timps switches.
# (json-config-daynight.cgi ships only with thingino-daynightd.)

. /var/www/x/auth.sh
require_auth

CFG=/etc/thingino.json

reply() {
	printf 'Status: %s\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1" "$2"
	exit 0
}

get() {
	local out="" k v d
	for k in color:true ircut:true ir850:true ir940:true white:false; do
		d=${k#*:}
		k=${k%%:*}
		v=$(jct "$CFG" get "daynight.controls.$k" 2>/dev/null) || v=$d
		case "$v" in true | false) ;; *) v=$d ;; esac
		out="$out${out:+,}\"$k\":$v"
	done
	reply "200 OK" "{\"controls\":{$out}}"
}

[ "$REQUEST_METHOD" = "POST" ] || get

LEN=${CONTENT_LENGTH:-0}
case "$LEN" in '' | *[!0-9]*) reply "411 Length Required" '{"error":"no length"}' ;; esac
[ "$LEN" -gt 0 ] && [ "$LEN" -le 512 ] || reply "413 Payload Too Large" '{"error":"bad size"}'
BODY=$(head -c "$LEN")
# only {"daynight":{"controls":{"<known>":true|false,...}}}
echo "$BODY" | grep -qE '^\{"daynight":\{"controls":\{("(color|ircut|ir850|ir940|white)":(true|false),?)+\}\}\}$' ||
	reply "400 Bad Request" '{"error":"unexpected body"}'
TMP=$(mktemp /tmp/dnc.XXXXXX) || reply "500 Internal Server Error" '{"error":"no temp file"}'
trap 'rm -f "$TMP"' EXIT
printf '%s' "$BODY" >"$TMP"
jct "$CFG" import "$TMP" >/dev/null 2>&1 || reply "500 Internal Server Error" '{"error":"write failed"}'
get
