#!/bin/sh

. /var/www/x/auth.sh
require_auth

THINGINO_CONFIG="${THINGINO_CONFIG:-/etc/thingino.json}"
BOOTSTRAP_CONFIG="${THINGINO_AGENT_BOOTSTRAP:-/etc/thingino-agent-bootstrap.json}"
TMP_FILE=""

cleanup() {
	[ -n "$TMP_FILE" ] && rm -f "$TMP_FILE"
}
trap cleanup EXIT

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e 's/\r/\\r/g' \
		-e 's/\n/\\n/g'
}

send_json() {
	status="${2:-200 OK}"
	printf "Status: %s\r\n" "$status"
	printf "Content-Type: application/json\r\n"
	printf "Cache-Control: no-store\r\n"
	printf "Pragma: no-cache\r\n"
	printf "Connection: close\r\n"
	printf "\r\n"
	printf "%s\n" "$1"
	exit 0
}

json_error() {
	code="${1:-500}"
	message="$2"
	http="${3:-500 Internal Server Error}"
	send_json "{\"ok\":false,\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "$http"
}

strip_json_string() {
	case "$1" in
		"" | null) printf '' ;;
		*) printf '%s' "$1" | sed -e 's/^"//' -e 's/"$//' ;;
	esac
}

normalize_bool() {
	case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
		1 | true | yes | on) printf 'true' ;;
		0 | false | no | off | "" | null) printf 'false' ;;
		*) json_error 422 "Invalid boolean value" "422 Unprocessable Entity" ;;
	esac
}

read_status() {
	token=$(jct "$THINGINO_CONFIG" get agent.token 2>/dev/null | tr -d '"\n\r')
	enabled=$(jct "$THINGINO_CONFIG" get agent.enabled 2>/dev/null | tr -d '"\n\r')
	tls=$(jct "$THINGINO_CONFIG" get agent.tls 2>/dev/null | tr -d '"\n\r')
	listen=$(jct "$THINGINO_CONFIG" get agent.listen 2>/dev/null | tr -d '"\n\r')
	port=$(jct "$THINGINO_CONFIG" get agent.port 2>/dev/null | tr -d '"\n\r')
	[ -n "$enabled" ] || enabled=false
	[ -n "$tls" ] || tls=false
	[ -n "$listen" ] || listen="127.0.0.1"
	[ -n "$port" ] || port=1998
	has_token=false
	[ -n "$token" ] && has_token=true
	pending=false
	[ -f "$BOOTSTRAP_CONFIG" ] && pending=true
	printf '{"ok":true,"agent":{"enabled":%s,"tls":%s,"listen":"%s","port":%s,"has_token":%s},"bootstrap_pending":%s}' \
		"$enabled" "$tls" "$(json_escape "$listen")" "$port" "$has_token" "$pending"
}

handle_get() {
	send_json "$(read_status)"
}

handle_post() {
	TMP_FILE=$(mktemp /tmp/agent-pair.XXXXXX)
	if [ -n "$CONTENT_LENGTH" ]; then
		dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$TMP_FILE"
	else
		cat >"$TMP_FILE"
	fi

	token=$(strip_json_string "$(jct "$TMP_FILE" get token 2>/dev/null)")
	tls=$(normalize_bool "$(jct "$TMP_FILE" get tls 2>/dev/null)")
	listen=$(strip_json_string "$(jct "$TMP_FILE" get listen 2>/dev/null)")
	port=$(strip_json_string "$(jct "$TMP_FILE" get port 2>/dev/null)")
	mqtt_host=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_host 2>/dev/null)")
	mqtt_port=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_port 2>/dev/null)")
	mqtt_username=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_username 2>/dev/null)")
	mqtt_password=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_password 2>/dev/null)")

	[ -n "$token" ] || json_error 422 "Bearer token is required" "422 Unprocessable Entity"
	[ -n "$listen" ] || listen="0.0.0.0"
	[ -n "$port" ] || port=1998
	case "$port" in
		*[!0-9]*) json_error 422 "Invalid agent port" "422 Unprocessable Entity" ;;
	esac

	if ! command -v thingino-agent-bootstrap >/dev/null 2>&1; then
		json_error 503 "thingino-agent-bootstrap helper is not installed" "503 Service Unavailable"
	fi

	# Prefer the shared helper for token + optional broker fields, then overlay
	# listen/tls/port into the bootstrap payload before restart.
	if ! thingino-agent-bootstrap install "$token" "$mqtt_host" "$mqtt_port" "$mqtt_username" "$mqtt_password"; then
		json_error 500 "Failed to write agent bootstrap"
	fi

	overlay=$(mktemp /tmp/agent-pair-overlay.XXXXXX)
	printf '{"agent":{"enabled":true,"tls":%s,"listen":"%s","port":%s,"token":"%s"}}\n' \
		"$tls" "$(json_escape "$listen")" "$port" "$(json_escape "$token")" >"$overlay"
	jct "$BOOTSTRAP_CONFIG" import "$overlay" >/dev/null 2>&1 || true
	rm -f "$overlay"

	(
		/etc/init.d/S95thingino-agent restart >/dev/null 2>&1 || true
		if [ -n "$mqtt_host" ] && [ -x /etc/init.d/S91mqttsub ]; then
			/etc/init.d/S91mqttsub restart >/dev/null 2>&1 || true
		fi
	) &

	send_json '{"ok":true,"status":"accepted","message":"Agent bootstrap written; agent restart queued"}'
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
