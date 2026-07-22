#!/bin/sh
# shellcheck disable=SC2039
# timps replacement for the day/night control CGI (same name, same URL).
# Translates the WebUI's {"cmd":..,"val":..} into timps /control calls;
# the IR/white-light and IR-cut GPIO helpers are kept as-is.

# Check authentication
. /var/www/x/auth.sh
require_auth

# derive timps's HTTP port + scheme from the config (http.port / http.https),
# fall back to 8880/http. When http.https is set timps serves TLS-only on that
# port, so this localhost bridge must use https + curl -k or every POST fails.
TIMPS_PORT=$(sed -n 's/^[[:space:]]*http\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' /etc/timps.conf 2>/dev/null | head -n1)
[ -z "$TIMPS_PORT" ] && TIMPS_PORT=8880
TIMPS_HTTPS=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' /etc/timps.conf 2>/dev/null | head -n1)
case "$TIMPS_HTTPS" in
	1 | true | yes | on)
		TIMPS_SCHEME=https
		TIMPS_CURL_K="-k"
		;;
	*)
		TIMPS_SCHEME=http
		TIMPS_CURL_K=""
		;;
esac
CONTROL_URL="${TIMPS_SCHEME}://127.0.0.1:${TIMPS_PORT}/control"

http_200() {
	printf 'Status: 200 OK\r\n'
}

http_400() {
	printf 'Status: 400 Bad Request\r\n'
}

http_412() {
	printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
	printf 'Content-Type: application/json\r\n'
	printf 'Pragma: no-cache\r\n'
	printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
	printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
	printf 'Connection: close\r\n'
	printf '\r\n'
}

json_error() {
	http_412
	json_header
	printf '{"error":{"code":412,"message":"%s"}}
' "$1"
	exit 0
}

json_ok() {
	http_200
	json_header
	case "$1" in
		\{*) printf '{"code":200,"result":"success","message":%s}
' "$1" ;;
		*) printf '{"code":200,"result":"success","message":"%s"}
' "$1" ;;
	esac
	exit 0
}

bad_request() {
	http_400
	echo
	echo "$1"
	exit 1
}

# Read POST data
read -r POST_DATA

# Parse JSON (supports quoted or numeric val)
cmd=$(printf '%s' "$POST_DATA" | awk -F'"' '/"cmd"/{for(i=1;i<=NF;i++){if($i=="cmd"){print $(i+2); exit}}}')
val=$(printf '%s' "$POST_DATA" | sed -n 's/.*"val"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\).*/\1/p')

[ -z "$cmd" ] && bad_request "missing required parameter cmd"
[ -z "$val" ] && bad_request "missing required parameter val"

case "$cmd" in
	auto)
		# toggle timps's native automatic day/night detection (the WebUI Auto
		# button sends val 1 to enable and 0 to disable)
		case "$val" in
			0 | false) AUTO=false ;;
			*) AUTO=true ;;
		esac
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d "{\"daynight\":{\"enabled\":$AUTO}}" >/dev/null 2>&1
		;;
	color)
		# manual override: disable auto detection, then set the ISP mode
		# (0 = day/color, 1 = night/b&w)
		case "$val" in
			0 | 1) ;;
			*) bad_request "invalid value for color" ;;
		esac
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d "{\"daynight\":{\"enabled\":false},\"image\":{\"running_mode\":$val}}" >/dev/null 2>&1
		;;
	daynight)
		# manual override: disable auto detection, force the ISP mode, then run
		# the board's daynight script - the same one timps's auto detection
		# calls - so the IR-cut filter, IR/white LEDs and the mode file
		# (/run/thingino/daynight_mode, read by the heartbeat) all switch too.
		# The /control force_mode is dedup-safe against the script's color hook.
		case "$val" in
			day | night) ;;
			*) bad_request "invalid value for daynight" ;;
		esac
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d "{\"daynight\":{\"enabled\":false},\"force_mode\":\"$val\"}" >/dev/null 2>&1
		command -v daynight >/dev/null 2>&1 && daynight "$val" >/dev/null 2>&1
		;;
	ir850 | ir940 | white)
		# manual light override: switch auto detection off first (like the stock
		# prudynt CGI), then drive the GPIO through thingino's light tool
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d '{"daynight":{"enabled":false}}' >/dev/null 2>&1
		light $cmd $val
		;;
	ircut)
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d '{"daynight":{"enabled":false}}' >/dev/null 2>&1
		ircut $val >/dev/null
		;;
esac

# All state data is provided by the (timps-aware) heartbeat CGIs, no need to
# build a payload here
json_ok
