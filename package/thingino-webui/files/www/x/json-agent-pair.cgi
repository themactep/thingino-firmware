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
	mqtt_enabled=$(jct "$THINGINO_CONFIG" get mqtt_sub.enabled 2>/dev/null | tr -d '"\n\r')
	mqtt_host=$(jct "$THINGINO_CONFIG" get mqtt_sub.host 2>/dev/null | tr -d '"\n\r')
	mqtt_port=$(jct "$THINGINO_CONFIG" get mqtt_sub.port 2>/dev/null | tr -d '"\n\r')
	mqtt_username=$(jct "$THINGINO_CONFIG" get mqtt_sub.username 2>/dev/null | tr -d '"\n\r')
	mqtt_password=$(jct "$THINGINO_CONFIG" get mqtt_sub.password 2>/dev/null | tr -d '"\n\r')

	[ -n "$enabled" ] || enabled=false
	[ -n "$tls" ] || tls=false
	[ -n "$listen" ] || listen="127.0.0.1"
	[ -n "$port" ] || port=1998
	[ -n "$mqtt_enabled" ] || mqtt_enabled=false
	[ -n "$mqtt_port" ] || mqtt_port=1883

	has_token=false
	[ -n "$token" ] && has_token=true
	pending=false
	[ -f "$BOOTSTRAP_CONFIG" ] && pending=true
	mqtt_configured=false
	[ -n "$mqtt_host" ] && mqtt_configured=true
	has_mqtt_password=false
	[ -n "$mqtt_password" ] && has_mqtt_password=true

	printf '{"ok":true,"agent":{"enabled":%s,"tls":%s,"listen":"%s","port":%s,"has_token":%s},"mqtt_sub":{"configured":%s,"enabled":%s,"host":"%s","port":%s,"username":"%s","has_password":%s},"bootstrap_pending":%s}' \
		"$enabled" "$tls" "$(json_escape "$listen")" "$port" "$has_token" \
		"$mqtt_configured" "$mqtt_enabled" "$(json_escape "$mqtt_host")" "$mqtt_port" \
		"$(json_escape "$mqtt_username")" "$has_mqtt_password" "$pending"
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
	update_mqtt=$(normalize_bool "$(jct "$TMP_FILE" get update_mqtt 2>/dev/null)")
	mqtt_host=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_host 2>/dev/null)")
	mqtt_port=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_port 2>/dev/null)")
	mqtt_username=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_username 2>/dev/null)")
	mqtt_password=$(strip_json_string "$(jct "$TMP_FILE" get mqtt_password 2>/dev/null)")

	existing_token=$(jct "$THINGINO_CONFIG" get agent.token 2>/dev/null | tr -d '"\n\r')
	if [ -z "$token" ]; then
		token="$existing_token"
	fi
	[ -n "$token" ] || json_error 422 "Bearer token is required" "422 Unprocessable Entity"
	[ -n "$listen" ] || listen="0.0.0.0"
	[ -n "$port" ] || port=1998
	case "$port" in
		*[!0-9]*) json_error 422 "Invalid agent port" "422 Unprocessable Entity" ;;
	esac

	if ! command -v thingino-agent-bootstrap >/dev/null 2>&1; then
		json_error 503 "thingino-agent-bootstrap helper is not installed" "503 Service Unavailable"
	fi

	# Empty MQTT fields preserve existing mqtt_sub (helper writes agent-only JSON).
	# Only rewrite broker settings when the operator explicitly updates them.
	install_host=
	install_port=
	install_user=
	install_pass=
	if [ "$update_mqtt" = true ]; then
		[ -n "$mqtt_host" ] || json_error 422 "MQTT broker address is required when updating MQTT settings" "422 Unprocessable Entity"
		install_host="$mqtt_host"
		install_port="${mqtt_port:-1883}"
		install_user="$mqtt_username"
		install_pass="$mqtt_password"
		# Keep the existing password when the operator leaves the masked field blank.
		if [ -z "$install_pass" ]; then
			install_pass=$(jct "$THINGINO_CONFIG" get mqtt_sub.password 2>/dev/null | tr -d '"\n\r')
		fi
	fi

	if ! thingino-agent-bootstrap install "$token" "$install_host" "$install_port" "$install_user" "$install_pass"; then
		json_error 500 "Failed to write agent bootstrap"
	fi

	overlay=$(mktemp /tmp/agent-pair-overlay.XXXXXX)
	printf '{"agent":{"enabled":true,"tls":%s,"listen":"%s","port":%s,"token":"%s"}}\n' \
		"$tls" "$(json_escape "$listen")" "$port" "$(json_escape "$token")" >"$overlay"
	jct "$BOOTSTRAP_CONFIG" import "$overlay" >/dev/null 2>&1 || true
	rm -f "$overlay"

	(
		/etc/init.d/S95thingino-agent restart >/dev/null 2>&1 || true
		if [ "$update_mqtt" = true ] && [ -x /etc/init.d/S91mqttsub ]; then
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
