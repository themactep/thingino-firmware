#!/bin/sh

# thingino day/night configuration access
# Backed by /etc/thingino.json under the "daynight" key.
# Defaults merged at build time by thingino-daynightd package.
# GET  → returns current daynight config
# POST → updates daynight config

. /var/www/x/auth.sh
require_auth

DOMAIN="daynight"
CONFIG_FILE="${THINGINO_CONFIG:-/etc/thingino.json}"
TMP_FILE=""
REQ_FILE=""

cleanup() {
	[ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
	[ -n "$REQ_FILE" ] && rm -f "$REQ_FILE"
}
trap cleanup EXIT

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

send_json() {
	status="${2:-200 OK}"
	printf 'Status: %s\r\n' "$status"
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n'
	printf 'Pragma: no-cache\r\n'
	printf 'Connection: close\r\n'
	printf '\r\n'
	printf '%s\n' "$1"
	exit 0
}

json_error() {
	code="${1:-400}"
	message="$2"
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

read_domain_json() {
	if [ ! -f "$CONFIG_FILE" ]; then
		printf '{}'
		return
	fi
	local data
	data=$(jct "$CONFIG_FILE" get "$DOMAIN" 2>/dev/null)
	case "$data" in
		"" | null) printf '{}' ;;
		*) printf '%s' "$data" ;;
	esac
}

handle_get() {
	send_json "$(read_domain_json)"
}

handle_post() {
	read_body
	jct "$CONFIG_FILE" import "$REQ_FILE" >/dev/null 2>&1
	if [ -f /run/daynightd.pid ]; then
		kill -HUP "$(cat /run/daynightd.pid)" 2>/dev/null || true
	fi
	send_json "$(read_domain_json)"
}

read_body() {
	REQ_FILE=$(mktemp /tmp/thingino-req.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
	else
		cat >"$REQ_FILE"
	fi
}

case "$REQUEST_METHOD" in
	GET | "")
		handle_get
		;;
	POST)
		handle_post
		;;
	*)
		json_error 405 "Method not allowed" "405 Method Not Allowed"
		;;
esac
