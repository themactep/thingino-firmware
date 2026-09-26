#!/bin/sh
# shellcheck disable=SC1091,SC2086,SC2119,SC2120,SC2329,SC3057
# shellcheck disable=SC2039
# timps's day/night + IR/white-light control bridge.

# Check authentication
. /var/www/x/auth.sh
require_auth

TIMPS_PORT=$(sed -n 's/^[[:space:]]*http\.port[[:space:]]*=[[:space:]]*\([0-9]\{1,\}\).*/\1/p' /etc/timps.conf 2>/dev/null | head -n1)
[ -z "$TIMPS_PORT" ] && TIMPS_PORT=8880
TIMPS_HTTPS=$(sed -n 's/^[[:space:]]*http\.https[[:space:]]*=[[:space:]]*\([0-9A-Za-z]*\).*/\1/p' /etc/timps.conf 2>/dev/null | head -n1 | tr '[:upper:]' '[:lower:]')
case "$TIMPS_HTTPS" in
	1 | 2 | true | yes | on)
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
	if [ "{" = "$(printf '%s' "$1" | cut -c1)" ]; then
		printf '{"code":200,"result":"success","message":%s}
' "$1"
	else
		printf '{"code":200,"result":"success","message":"%s"}
' "$1"
	fi
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
		case "$val" in
			day | night) ;;
			*) bad_request "invalid value for daynight" ;;
		esac
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d "{\"daynight\":{\"enabled\":false},\"force_mode\":\"$val\"}" >/dev/null 2>&1
		command -v daynight >/dev/null 2>&1 && daynight "$val" >/dev/null 2>&1
		;;
	ir850 | ir940 | white)
		case "$val" in
			0 | 1 | on | off | toggle | read) ;;
			*) bad_request "invalid value for $cmd" ;;
		esac
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d '{"daynight":{"enabled":false}}' >/dev/null 2>&1
		light $cmd $val
		;;
	ircut)
		case "$val" in
			0 | 1 | on | off | toggle | status | read) ;;
			*) bad_request "invalid value for ircut" ;;
		esac
		curl -s $TIMPS_CURL_K -m 5 -X POST "$CONTROL_URL" \
			-d '{"daynight":{"enabled":false}}' >/dev/null 2>&1
		ircut $val >/dev/null
		;;
	*)
		bad_request "unknown cmd"
		;;
esac

# All state data is provided by the (timps-aware) heartbeat CGIs, no need to
# build a payload here
json_ok
